# Disclaimer / 免责声明

## 中文

本项目是一份**技术研究与教育资料**，仅用于在你**合法拥有并有权使用**的 macOS 设备上运行容器化开发环境。

1. **合规风险自负**：本项目涉及在 Intel 黑苹果（非 Apple 原装硬件）上运行 macOS 的相关场景。macOS 的最终用户许可协议（EULA）可能不允许在非 Apple 硬件上安装或运行 macOS；使用本项目前请确认你所在地区的法律与 Apple 条款。作者不对任何因使用本项目而产生的法律、版权或合规问题负责。
2. **无担保**：软件按"现状"（AS IS）提供，不附带任何明示或暗示的担保，包括但不限于适销性、特定用途适用性和不侵权。
3. **数据安全**：脚本会修改 `~/.zshrc`、安装第三方二进制文件到用户目录、下载并运行 VM 镜像。请在理解每一步作用后使用，并自行备份重要数据。
4. **第三方组件**：QEMU（GPL-2.0）、Lima（Apache-2.0）、Colima（MIT）、Ubuntu 云镜像及各预编译二进制均属各自作者所有，遵循各自许可。本项目不重新分发其源码，仅提供下载与编排脚本。
5. **非官方**：本项目与 Docker, Inc.、Apple Inc.、QEMU、Lima、Colima 项目无任何关联、背书或赞助关系。

使用本项目即表示你已阅读并同意上述条款。

## English

This project is **technical research and educational material**, intended only for
running a containerized development environment on macOS devices that you **lawfully
own and are entitled to use**.

1. **Compliance**: This project touches setups involving Intel Hackintoshes (non-Apple hardware). The macOS EULA may not permit installing/running macOS on non-Apple hardware. Verify the laws in your jurisdiction and Apple's terms before use. The author is not responsible for any legal, copyright, or compliance issues arising from use.
2. **No warranty**: The software is provided "AS IS", without warranties of any kind, express or implied, including but not limited to merchantability, fitness for a particular purpose, and non-infringement.
3. **Data safety**: The scripts modify `~/.zshrc`, install third-party binaries under your home directory, and download/run VM images. Understand each step and back up important data.
4. **Third-party components**: QEMU (GPL-2.0), Lima (Apache-2.0), Colima (MIT), the Ubuntu cloud image, and prebuilt binaries belong to their respective authors and follow their own licenses. This project does not redistribute their source, only download/orchestration scripts.
5. **Unofficial**: This project is not affiliated with, endorsed by, or sponsored by Docker, Inc., Apple Inc., or the QEMU/Lima/Colima projects.

By using this project you acknowledge having read and accepted the above.
