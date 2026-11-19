# Troubleshooting / 故障排查

> 中文与英文混排，便于中英文开发者搜索。Each section has CN + EN notes.

---

## `Hypervisor check failed` (Docker Desktop) / 仍然报这个

**EN**: Expected. Docker Desktop can never work on a broken-HVF Hackintosh. Do not
try to force it via `EngineTypeMac` / `settings-store.json` — the fatal check runs
in `com.docker.backend` regardless of engine.

**中文**: 预期之中。Docker Desktop 在这类机器上永远起不来，别再改 `EngineTypeMac` 了。请改用本方案的 TCG 路线。

---

## `VZErrorDomain Code=1` / Colima VZ 失败

**EN**: Apple Virtualization.framework is unavailable. Use `--vm-type=qemu` (the
installer configures this). Never use `vz`.

**中文**: Apple VZ 框架不可用。必须用 `qemu` 类型，不要用 `vz`。

---

## `ret = HV_ERROR (0xfae94001)` from QEMU / QEMU 仍 tried HVF

**EN**: The shim isn't being used. Verify:
```bash
~/.local/qemu/bin/qemu-system-x86_64 -M none -accel help   # must list 'tcg'
ps -ww -p $(pgrep -f qemu-system-x86_64.real | head -1) -o command= | grep accel
# should show: -machine q35,accel=tcg
```
Make sure `$HOME/.local/qemu/bin` precedes any real QEMU on PATH.

**中文**: shim 没生效。确认 PATH 中 `~/.local/qemu/bin` 在真实 QEMU 之前，并检查上面命令输出含 `accel=tcg`。

---

## `usernet unable to resolve IP for SSH forwarding`

**EN**: Lima's `user-v2` network is in use. The Lima config must have **no**
`networks:` block. Check:
```bash
grep -A2 '^networks:' ~/.colima/_lima/colima/lima.yaml   # must print nothing
```
Delete that block and `docker-up` again.

**中文**: 配置文件里还有 `networks:` 段。删除它（含其下的 `- lima: user-v2`）再启动，让 Lima 使用默认 SLIRP。

---

## `Network is unreachable` / DNS fails in guest / guest DNS 失败

**EN**: Check `/etc/resolv.conf` inside the VM:
```bash
ssh -p <SSH_PORT> -i ~/.colima/_lima/_config/user george@127.0.0.1 \
  'cat /etc/resolv.conf; getent hosts registry-1.docker.io'
```
It should contain `8.8.8.8`. `docker-up` fixes this idempotently; if the VM was
suspended, run `docker-down && docker-up`.

**中文**: guest 里 resolv.conf 应包含 8.8.8.8。`docker-up` 会自动修；若虚拟机休眠过，执行 `docker-down && docker-up`。

---

## `docker.sock` EOF / `error during connect ... EOF`

**EN**: The Lima hostagent forwards the socket. Check:
```bash
curl --unix-socket ~/.colima/default/docker.sock http://localhost/_ping   # OK
```
If not OK, the VM may be rebooting; wait and re-run `docker-up`. Avoid creating
your own `ssh -L` forward — it conflicts with Lima's.

**中文**: socket 由 Lima hostagent 维护。返回 `OK` 才正常。不要自己建 `ssh -L` 隧道，会和 Lima 冲突。

---

## `docker-credential-desktop: executable file not found`

**EN**: Add Docker Desktop's bin dir to PATH (the installer does this):
```bash
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
```

**中文**: 把 Docker.app 的 bin 目录加入 PATH（安装脚本已处理）。

---

## Very slow / 很慢

**EN**: TCG is pure software emulation. Cold boot 3–5 min; `docker pull` of large
images can take minutes. Reduce CPU/memory only if host is constrained. For heavy
builds use a real Apple-silicon machine or GitHub Actions.

**中文**: TCG 是纯软件模拟，冷启动 3–5 分钟、拉大镜像较慢属正常。重负载建议放到真机或 GitHub Actions。

---

## Need a clean restart / 彻底重启

```bash
docker-down
rm -f ~/.colima/default/docker.sock ~/.colima/docker.sock
docker-up
```
