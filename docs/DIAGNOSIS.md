# Diagnosis: why Docker fails on Intel Hackintosh / 根因分析

## Symptom / 现象

On an Intel Hackintosh (e.g. iMac19,1, macOS Sequoia), all of these fail:

- Docker Desktop → `FAIL: Hypervisor framework fails` / `Hypervisor check failed`
- `colima start --vm-type=vz` → `VZErrorDomain Code=1 Internal Virtualization error. The virtual machine failed to start.`
- `qemu -accel hvf` → `Error: ret = HV_ERROR (0xfae94001, at ../accel/hvf/hvf-all.c:221)`

在 Intel 黑苹果上，Docker Desktop、Colima VZ、QEMU-HVF 全部以 Hypervisor 相关错误失败。

## Investigation / 排查过程

### 1. Docker Desktop disassembly / 反汇编

Disassembling `com.docker.backend` (Docker Desktop 4.99, build 245822) revealed two checks:

- `compatibilitycheck.cpuSupportedCheck.Run` runs
  `/usr/sbin/sysctl sysctl.proc_translated kern.hv_support`.
  On Intel, `sysctl.proc_translated` is an unknown OID → the command exits 1.
  This is only a **warning**, not the fatal cause.
- `compatibilitycheck.virtualizationSupportedCheck.Run` calls a C helper doing
  `hv_vm_create(0); hv_vm_destroy()`. Return code 1 yields the literal string
  **`Hypervisor check failed`** — this is the **fatal** check.

### 2. Direct HVF test / 直接测试 Hypervisor.framework

```swift
import Hypervisor
let r = hv_vm_create(hv_vm_options_t(0))
print(r)   // -85377017 on the affected machine → HVF BROKEN
```

`kern.hv_support` reads `1`, so the surface check passes, but the actual
`hv_vm_create()` syscall fails. This is the definitive root cause.

### 3. The machine is a Hackintosh / 机器是黑苹果

```
$ nvram boot-args
igfxonln=1 -amfipassbeta -lilubetaall

$ kextstat | grep -iE 'lilu|amfi|virtualsmc'
as.vit9696.Lilu, com.dhinakg.AMFIPass, as.vit9696.VirtualSMC

$ csrutil status
System Integrity Protection status: unknown (Custom Configuration)  # SIP off
```

Apple's Hypervisor.framework performs entitlement/host checks that do not pass
on this non-genuine-Apple configuration. No Docker/Colima setting can fix it.

## Conclusion / 结论

The only reliable escape is to avoid Hypervisor.framework entirely: **QEMU TCG**
(`-accel tcg`), a pure software CPU emulator that needs no hypervisor privileges.
This project builds a complete, reproducible Docker workflow on top of TCG.

唯一可靠的出路是彻底绕开 Hypervisor.framework —— 使用不需要任何虚拟化权限的
**QEMU TCG 纯软件模拟**。本项目在此基础上搭建了完整、可复现的 Docker 工作流。

## Community status / 社区现状

No public issue has a confirmed fix for this native-Intel scenario:
[docker/for-mac#7641](https://github.com/docker/for-mac/issues/7641) is open with
zero comments. The known `ryzen-hypervisor.framework` / OpenCore-G513RM shims
target AMD Hackintoshes with kext injection and do not apply here.
