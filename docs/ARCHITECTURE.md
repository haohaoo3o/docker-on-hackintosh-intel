# Architecture / 架构

```
┌───────────────────────────── host (Intel Hackintosh, macOS) ─────────────────────────────┐
│                                                                                          │
│  docker CLI ──► docker context 'colima' ──► ~/.colima/default/docker.sock                │
│                                                    ▲                                    │
│                                       Lima hostagent port-forward (auto)                 │
│                                                    │                                    │
│  ~/.local/qemu/bin/qemu-system-x86_64  (wrapper)                                         │
│            │  exec python3 qemu-shim.py "$@"                                             │
│            ▼                                                                            │
│  qemu-shim.py:  accel=hvf ─► accel=tcg ;  -cpu host ─► -cpu qemu64 ;  inject -L firmware │
│            │  os.execv(real qemu)                                                        │
│            ▼                                                                            │
│  qemu-system-x86_64.real  ── TCG (no Hypervisor.framework) ──► Ubuntu 24.04 guest        │
│                                        (SLIRP user net, dockerd, overlay2)               │
│                                                                                          │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

## Components / 组件

| Component | Path (default) | Role |
|---|---|---|
| QEMU real binary | `~/.local/qemu/bin/qemu-system-x86_64.real` | TCG-capable emulator (prebuilt Intel macOS) |
| QEMU wrapper | `~/.local/qemu/bin/qemu-system-x86_64` | entry point → shim |
| Shim | `~/.local/qemu/share/qemu-shim.py` | rewrite HVF args to TCG |
| Firmware | `~/.local/qemu/share/*.fd`, `~/.local/share/qemu` | SeaBIOS/OVMF for Lima |
| Lima / Colima | `~/.local/bin/{limactl,colima}` | VM lifecycle, socket forwarding |
| VM config | `~/.colima/_lima/colima/lima.yaml` | **no `networks:` block** → SLIRP |
| Root disk | `~/.colima/_lima/colima/disk` | Colima Docker image |
| Sockets | `~/.colima/default/docker.sock` | host side of dockerd |
| Management | `~/.local/bin/{docker-up,docker-down}` | start / stop |

## Design decisions / 设计决策

1. **Shim, not patched binary.** Patching/re-signing QEMU loses the Hypervisor
   entitlement and is fragile; a transparent argv rewrite keeps Lima's feature
   probes (`-accel help`) working and survives QEMU upgrades.
2. **No `networks:` block.** Lima's `user-v2` network resolves the guest IP via
   the guest agent; under slow TCG boots this races and fails with
   `usernet unable to resolve IP for SSH forwarding`. Omitting the block selects
   classic QEMU SLIRP, which forwards ports without guest-IP discovery.
3. **Guest DNS fix in provision.** `/etc/resolv.conf` may be a dangling symlink
   early in boot; the provision script points it at public DNS and restarts dockerd.
4. **Socket forward via Lima hostagent.** Using Lima's `portForwards.guestSocket`
   is more robust than a hand-rolled `ssh -L`, which can die on guest reboots.

## Lifecycle / 生命周期

1. `docker-up` → `limactl start colima` → shim forces TCG → guest boots →
   Lima forwards docker.sock → docker context switched to `colima`.
2. `docker-down` → `limactl stop colima`.

All steps are idempotent. 所有步骤均幂等。

## Trade-offs / 取舍

- TCG is **software emulation**: expect 3–5 min cold boot and slower builds.
- Intended for local development and light CI; offload heavy builds to real hardware/GHA.
