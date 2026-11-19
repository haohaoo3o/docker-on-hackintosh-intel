#!/bin/bash
# install.sh — Docker on Intel Hackintosh via QEMU-TCG.
#
# Reproducible, user-level (no sudo required for the toolchain) installer that
# makes `docker run / build / compose` work on an Intel Mac where Apple's
# Hypervisor.framework is broken (Docker Desktop, VZ and QEMU-HVF all fail).
#
# See README.md before running. Supports macOS Intel only.

set -uo pipefail

# --------------------------------------------------------------------------
# Config (override via environment)
# --------------------------------------------------------------------------
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/haohaoo3o/docker-on-hackintosh-intel/main}"
QEMU_DIR="${QEMU_DIR:-$HOME/.local/qemu}"
QEMU_DMG_URL="${QEMU_DMG_URL:-https://github.com/albanread/Aldershot/releases/download/BOX-x64-mac-2026.10.18/BOX-x64-mac-2026.10.18.4.dmg}"
COLIMA_VERSION="${COLIMA_VERSION:-v0.10.3}"
LIMA_VERSION="${LIMA_VERSION:-v2.3.0}"
COLIMA_CORE_VERSION="${COLIMA_CORE_VERSION:-v0.10.4}"
IMAGE_NAME="ubuntu-24.04-minimal-cloudimg-amd64-docker.raw.gz"
LIMA_HOME_DIR="${LIMA_HOME_DIR:-$HOME/.colima/_lima}"
INSTANCE="colima"
CPU="${CPU:-2}"
MEMORY_MIB="${MEMORY_MIB:-4096}"
DISK="${DISK:-20GiB}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

C_OK=$'\033[0;32m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[0;31m'; C_INFO=$'\033[0;36m'; C_OFF=$'\033[0m'
log()  { echo "${C_OK}[+]$C_OFF $*"; }
warn() { echo "${C_WARN}[!]$C_OFF $*"; }
err()  { echo "${C_ERR}[x]$C_OFF $*" >&2; }
info() { echo "${C_INFO}[i]$C_OFF $*"; }
need() { command -v "$1" >/dev/null 2>&1; }

# Resolve a repo file: prefer a local clone next to this script, fall back to raw URL.
# Usage: fetch_file <relative-path> <dest>
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
fetch_file() {
  local rel="$1" dest="$2" local_src="$SCRIPT_DIR/$1"
  if [ -f "$local_src" ]; then
    cp "$local_src" "$dest" && return 0
  fi
  curl -fSL -o "$dest" "$REPO_RAW/$rel"
}

# --------------------------------------------------------------------------
# Preflight
# --------------------------------------------------------------------------
preflight() {
  log "Preflight checks"
  if [ "$(uname -s)" != "Darwin" ]; then err "macOS only."; exit 1; fi
  if [ "$(uname -m)" != "x86_64" ]; then
    err "This project targets Intel Macs (x86_64). On Apple Silicon just use Docker Desktop."
    exit 1
  fi
  for t in curl unzip tar hdiutil python3; do
    need "$t" || { err "Missing required tool: $t"; exit 1; }
  done
  HV=$(sysctl -n kern.hv_support 2>/dev/null || echo 0)
  info "kern.hv_support=$HV (the shim forces TCG regardless)"
  mkdir -p "$BIN_DIR" "$QEMU_DIR/bin" "$QEMU_DIR/share" "$QEMU_DIR/Frameworks"
}

# --------------------------------------------------------------------------
# 1. QEMU (TCG-capable, prebuilt for Intel macOS)
# --------------------------------------------------------------------------
install_qemu() {
  log "Setting up QEMU (TCG)"
  if [ -x "$QEMU_DIR/bin/qemu-system-x86_64.real" ]; then
    info "QEMU already installed: $($QEMU_DIR/bin/qemu-system-x86_64.real --version | head -1)"
  else
    local tmp; tmp=$(mktemp -d)
    info "Downloading QEMU (~424MB) from $QEMU_DMG_URL"
    curl -fL --retry 3 -o "$tmp/BOX.dmg" "$QEMU_DMG_URL" || { err "QEMU download failed."; exit 1; }
    local vol
    vol=$(hdiutil attach "$tmp/BOX.dmg" -nobrowse | grep '/Volumes/' | tail -1 | awk -F'\t' '{print $NF}')
    [ -n "$vol" ] || { err "Could not mount QEMU dmg."; exit 1; }
    local app="$vol/BOX.app/Contents"
    cp "$app/MacOS/qemu-system-x86_64" "$QEMU_DIR/bin/qemu-system-x86_64.real"
    cp -R "$app/Frameworks/." "$QEMU_DIR/Frameworks/"
    cp -R "$app/Resources/qemu/." "$QEMU_DIR/share/"
    hdiutil detach "$vol" >/dev/null 2>&1 || true
    rm -rf "$tmp"
    chmod +x "$QEMU_DIR/bin/qemu-system-x86_64.real"
    chmod +x "$QEMU_DIR/Frameworks/"*.dylib 2>/dev/null || true
  fi

  # Firmware in every path Lima probes.
  mkdir -p "$QEMU_DIR/share/qemu" "$HOME/.local/share/qemu"
  for fw in edk2-x86_64-code.fd edk2-i386-vars.fd; do
    [ -f "$QEMU_DIR/share/$fw" ] || { err "Missing firmware $fw"; exit 1; }
    cp "$QEMU_DIR/share/$fw" "$QEMU_DIR/share/qemu/$fw" 2>/dev/null || true
    cp "$QEMU_DIR/share/$fw" "$HOME/.local/share/qemu/$fw" 2>/dev/null || true
  done

  # qemu-img: use the one shipped with the Android SDK if available.
  if ! need qemu-img; then
    local qimg
    qimg=$(find "$HOME/Library/Android/sdk" -name qemu-img -type f 2>/dev/null | head -1)
    if [ -n "$qimg" ]; then
      cat > "$QEMU_DIR/bin/qemu-img" <<EOF
#!/bin/bash
export DYLD_LIBRARY_PATH="$HOME/Library/Android/sdk/emulator/lib64:\$DYLD_LIBRARY_PATH"
exec "$qimg" "\$@"
EOF
      chmod +x "$QEMU_DIR/bin/qemu-img"
      info "qemu-img wrapper created from Android SDK"
    else
      warn "qemu-img not found; install Android SDK or provide one on PATH if image ops fail."
    fi
  fi

  # Install shim + wrapper.
  fetch_file "scripts/qemu-shim.py" "$QEMU_DIR/share/qemu-shim.py" \
    || { err "Failed to fetch qemu-shim.py (offline? copy it manually)."; exit 1; }
  chmod +x "$QEMU_DIR/share/qemu-shim.py"
  cat > "$QEMU_DIR/bin/qemu-system-x86_64" <<EOF
#!/bin/bash
# Wrapper: rewrite HVF -> TCG. See qemu-shim.py.
QEMU_SHIM_DIR="$QEMU_DIR" exec python3 "$QEMU_DIR/share/qemu-shim.py" "\$@"
EOF
  chmod +x "$QEMU_DIR/bin/qemu-system-x86_64"

  # Smoke test: probe must still list both accelerators.
  local accels
  accels=$("$QEMU_DIR/bin/qemu-system-x86_64" -M none -accel help 2>&1 | tr '\n' ' ')
  info "QEMU accelerators: $accels"
  echo "$accels" | grep -q tcg || { err "TCG not detected in QEMU shim."; exit 1; }
  # Real boot must use TCG (SeaBIOS should appear).
  local logf; logf=$(mktemp)
  ( "$QEMU_DIR/bin/qemu-system-x86_64" -M pc -accel hvf -m 128 \
      -drive file=/dev/null,format=raw -nographic -no-reboot >"$logf" 2>&1 ) &
  local p=$!; sleep 3; kill "$p" 2>/dev/null; wait "$p" 2>/dev/null
  grep -qi 'SeaBIOS' "$logf" && info "TCG boot smoke test: OK" || warn "TCG smoke test inconclusive (continuing)"
  rm -f "$logf"
}

# --------------------------------------------------------------------------
# 2. Lima / Colima user-level binaries
# --------------------------------------------------------------------------
install_tooling() {
  log "Installing Lima + Colima (user-level)"
  need limactl || {
    local tmp; tmp=$(mktemp -d); cd "$tmp"
    curl -fL --retry 3 -o lima.tgz \
      "https://github.com/lima-vm/lima/releases/download/$LIMA_VERSION/lima-$LIMA_VERSION-Darwin-x86_64.tar.gz"
    tar xzf lima.tgz
    cp -R ./bin/. "$BIN_DIR/"
    rm -rf "$HOME/.local/share/lima"
    mkdir -p "$HOME/.local/share"
    cp -R ./share/lima "$HOME/.local/share/lima"
    cd - >/dev/null; rm -rf "$tmp"
  }
  need colima || {
    curl -fL --retry 3 -o "$BIN_DIR/colima" \
      "https://github.com/abiosoft/colima/releases/download/$COLIMA_VERSION/colima-Darwin-x86_64"
    chmod +x "$BIN_DIR/colima"
  }
  info "limactl: $(limactl --version 2>&1 | head -1)"
  info "colima:  $(colima --version 2>&1 | head -1)"
}

# --------------------------------------------------------------------------
# 3. Prepare the Lima instance (image + config with NO networks: block)
# --------------------------------------------------------------------------
prepare_instance() {
  log "Preparing Lima instance '$INSTANCE'"
  export PATH="$BIN_DIR:$QEMU_DIR/bin:$PATH"

  local inst_dir="$LIMA_HOME_DIR/$INSTANCE"
  mkdir -p "$inst_dir" "$LIMA_HOME_DIR/_disks/$INSTANCE" "$LIMA_HOME_DIR/_config"
  local sock_dir="$HOME/.colima/default"
  mkdir -p "$sock_dir"
  local docker_sock="$sock_dir/docker.sock"
  local containerd_sock="$sock_dir/containerd.sock"

  if [ ! -f "$inst_dir/lima.yaml" ]; then
    info "Downloading Docker-enabled Ubuntu image (~600MB)"
    local cache_dir="$HOME/Library/Caches/colima/caches"
    mkdir -p "$cache_dir"
    local img="$cache_dir/$IMAGE_NAME.gz"
    if [ ! -f "$img" ]; then
      curl -fL --retry 3 -o "$img" \
        "https://github.com/abiosoft/colima-core/releases/download/$COLIMA_CORE_VERSION/$IMAGE_NAME"
    fi
    # Decompress to a raw disk once.
    local disk="$inst_dir/disk"
    if [ ! -f "$disk" ]; then
      info "Preparing root disk from image (this can take a minute)"
      gzip -dc "$img" > "$disk"
    fi

    fetch_file "scripts/lima-colima.yaml.tmpl" "$inst_dir/lima.yaml.tmp"
    sed -e "s|__IMAGE_PATH__|$disk|" \
        -e "s|__CPUS__|$CPU|" \
        -e "s|__MEMORY__|${MEMORY_MIB}MiB|" \
        -e "s|__DISK__|$DISK|" \
        -e "s|__DOCKER_SOCK__|$docker_sock|" \
        -e "s|__CONTAINERD_SOCK__|$containerd_sock|" \
        "$inst_dir/lima.yaml.tmp" > "$inst_dir/lima.yaml"
    rm -f "$inst_dir/lima.yaml.tmp"
    echo "$LIMA_VERSION" > "$inst_dir/lima-version"
    info "Instance config written (no networks: block -> SLIRP)."
  else
    info "Instance already configured."
  fi

  # Extra data disk (Colima expects it; harmless if unused).
  local dd="$LIMA_HOME_DIR/_disks/$INSTANCE/datadisk"
  [ -f "$dd" ] || truncate -s 20G "$dd"

  limactl template validate "$inst_dir/lima.yaml" >/dev/null 2>&1 \
    && info "Lima config validated" || warn "Lima config validation warning (continuing)"
}

# --------------------------------------------------------------------------
# 4. Management scripts
# --------------------------------------------------------------------------
install_management_scripts() {
  log "Installing docker-up / docker-down"
  fetch_file "scripts/docker-up" "$BIN_DIR/docker-up" || { err "fetch docker-up failed"; exit 1; }
  fetch_file "scripts/docker-down" "$BIN_DIR/docker-down" || { err "fetch docker-down failed"; exit 1; }
  chmod +x "$BIN_DIR/docker-up" "$BIN_DIR/docker-down"

  # Shell profile PATH additions (idempotent).
  local profile="$HOME/.zshrc"; [ -f "$profile" ] || profile="$HOME/.bash_profile"
  grep -q 'docker-on-hackintosh-intel' "$profile" 2>/dev/null || {
    cat >> "$profile" <<EOF

# >>> docker-on-hackintosh-intel >>>
export PATH="$BIN_DIR:/Applications/Docker.app/Contents/Resources/bin:\$PATH"
export LIMA_HOME="$LIMA_HOME_DIR"
# <<< docker-on-hackintosh-intel <<<
EOF
    info "Added PATH/LIMA_HOME to $profile"
  }
}

# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------
main() {
  echo "============================================================"
  echo " Docker on Intel Hackintosh — QEMU-TCG installer"
  echo "============================================================"
  preflight
  install_qemu
  install_tooling
  prepare_instance
  install_management_scripts
  echo
  log "Install complete. Start Docker with:"
  echo "    export PATH=\"$BIN_DIR:\$PATH\""
  echo "    docker-up"
  echo "Then verify:  docker run --rm hello-world"
  warn "First boot under TCG is slow (3-5 min). Be patient."
}

main "$@"
