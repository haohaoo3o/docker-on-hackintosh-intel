# Docker on Intel Hackintosh (QEMU-TCG)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-Intel%20x86__64-blue.svg)](https://github.com/haohaoo3o/docker-on-hackintosh-intel)

> **中文**: 让 Docker 在 Apple Hypervisor.framework 损坏的 Intel 黑苹果上真正跑起来 —— 通过 QEMU 纯软件虚拟化（TCG）绕过 HVF，实现 `docker run / build / compose` 全功能。
>
> **EN**: Make Docker actually work on Intel Hackintoshes where Apple's Hypervisor.framework is broken — bypass HVF with QEMU's pure-software TCG emulation, enabling full `docker run / build / compose`.

---

## Why / 为什么需要它

On a stock Mac, Docker Desktop, Apple's Virtualization.framework (VZ), and QEMU-HVF all rely on `hv_vm_create()` from Hypervisor.framework. On many **Intel Hackintoshes** this call fails (`HV_ERROR`), producing the infamous:

- `Docker Desktop: Hypervisor check failed`
- `Colima VZ: VZErrorDomain Code=1 Internal Virtualization error`
- `QEMU -accel hvf: ret = HV_ERROR (0xfae94001)`

Root cause confirmed by disassembly of `com.docker.backend` and a direct Swift `hv_vm_create()` test — see [docs/DIAGNOSIS.md](docs/DIAGNOSIS.md).

The fix: **TCG** — QEMU's CPU emulator — needs no hypervisor privileges at all. This project wires TCG into Lima/Colima transparently and gives you a normal `docker` CLI experience.

在原生 Mac 上，Docker Desktop、VZ、QEMU-HVF 都依赖 Hypervisor.framework 的 `hv_vm_create()`。在很多 **Intel 黑苹果**上这个调用直接失败，于是出现 "Hypervisor check failed" 等经典报错。解法是改用完全不需要虚拟化权限的 **QEMU TCG 软件模拟**。本项目把 TCG 透明接入 Lima/Colima，让你照常使用 `docker` 命令。

---

## Features / 特性

- ✅ One-command installer, **no sudo for the toolchain** (user-level installs) / 一键安装，工具链无需 sudo
- ✅ Transparent `HVF → TCG` shim (Lima capability probes preserved) / 透明的 HVF→TCG 改写 shim
- ✅ Correct SLIRP networking + guest DNS fix (avoids TCG-slow `user-v2` IP resolution) / 正确的 SLIRP 网络与 guest DNS 修复
- ✅ Idempotent `docker-up` / `docker-down` management / 幂等的启停脚本
- ✅ Verified: pull / run / build / compose / 已验证：拉取/运行/构建/compose

---

## Requirements / 前置要求

| Item | Note |
|---|---|
| macOS on **Intel x86_64** | Apple Silicon does NOT need this — use Docker Desktop |
| Python 3, curl, unzip, hdiutil | Present on stock macOS |
| ~1.5 GB free disk | QEMU + Ubuntu Docker image + VM disk |
| Internet | Downloads QEMU, Lima, Colima, Ubuntu image |

> On Apple Silicon this project intentionally refuses to run. 在 Apple Silicon 上本项目会拒绝运行。

---

## Quick start / 快速开始

```bash
git clone https://github.com/haohaoo3o/docker-on-hackintosh-intel.git
cd docker-on-hackintosh-intel
bash install.sh

# reload shell (installer appends PATH/LIMA_HOME to ~/.zshrc)
source ~/.zshrc

# start the engine (first boot under TCG: 3–5 min)
docker-up

# verify
docker run --rm hello-world
docker compose version
```

Then use `docker` normally. 之后即可正常使用 `docker`。

### Everyday commands / 日常命令

```bash
docker-up        # start engine (safe to run repeatedly) / 启动（可重复执行）
docker-down      # stop engine / 停止
docker context ls # 'colima' context is active / 'colima' 上下文已激活
```

---

## What the installer does / 安装脚本做了什么

1. Downloads a **prebuilt QEMU 11.1 (Intel macOS, TCG+HVF capable)** and installs it under `~/.local/qemu`.
2. Installs a Python shim that rewrites `-machine ...,accel=hvf` → `accel=tcg` and `-cpu host` → `-cpu qemu64`, while leaving `-accel help` probes intact.
3. Installs user-level `limactl` + `colima`.
4. Downloads Colima's Docker-enabled Ubuntu 24.04 image and writes a Lima config **with no `networks:` block** (default SLIRP) and with docker/containerd socket port-forwards.
5. Installs `docker-up` / `docker-down` and updates your shell profile.

详见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

---

## Docs / 文档

- [Diagnosis: why HVF fails / 根因分析](docs/DIAGNOSIS.md)
- [Architecture / 架构](docs/ARCHITECTURE.md)
- [Troubleshooting / 故障排查](docs/TROUBLESHOOTING.md)
- [Disclaimer / 免责声明](DISCLAIMER.md)

---

## Acknowledgements / 致谢

- [QEMU](https://www.qemu.org/) (GPL-2.0) — TCG emulation
- [Prebuilt QEMU for Intel macOS](https://github.com/albanread/qemu-intel-mac) — `albanread/Aldershot` release
- [Lima](https://github.com/lima-vm/lima) (Apache-2.0) & [Colima](https://github.com/abiosoft/colima) (MIT) — VM orchestration
- Community threads that documented the dead-ends: [docker/for-mac#7641](https://github.com/docker/for-mac/issues/7641), [lima#3433](https://github.com/lima-vm/lima/issues/3433)

## License / 许可

MIT — see [LICENSE](LICENSE). Third-party components keep their own licenses; see [DISCLAIMER.md](DISCLAIMER.md).
