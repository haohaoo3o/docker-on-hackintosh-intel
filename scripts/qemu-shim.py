#!/usr/bin/env python3
"""
qemu-shim.py — force QEMU to use TCG software emulation on hosts where
Apple's Hypervisor.framework (HVF) is broken (notably Intel Hackintoshes).

Lima launches QEMU with `-machine q35,accel=hvf -cpu host,...`. On a
Hackintosh, `hv_vm_create()` fails with HV_ERROR, so the VM never boots.
This shim transparently rewrites those arguments just before exec:

    -machine q35,accel=hvf     ->  -machine q35,accel=tcg
    -accel hvf                 ->  -accel tcg
    -cpu host,...              ->  -cpu qemu64        (TCG lacks host CPUID flags)

Capability probes (e.g. `qemu-system-x86_64 -M none -accel help`) are left
untouched, so Lima can still detect the available accelerators correctly.

Usage: place this file next to a wrapper that calls it, e.g.

    #!/bin/bash
    exec python3 /path/to/qemu-shim.py "$@"

and put that wrapper on PATH ahead of the real qemu-system-x86_64.
"""

import os
import sys

# Where the real QEMU binary / firmware live. Overridable by environment so
# the same shim works in any install layout.
QEMU_DIR = os.environ.get("QEMU_SHIM_DIR", os.path.expanduser("~/.local/qemu"))
REAL = os.environ.get("QEMU_SHIM_REAL", os.path.join(QEMU_DIR, "bin", "qemu-system-x86_64.real"))
FIRMWARE_DIR = os.path.join(QEMU_DIR, "share")

# TCG-safe baseline CPU. "qemu64" is universally supported; "max" is faster
# but can expose instructions TCG cannot translate on some hosts.
TCG_CPU = os.environ.get("QEMU_SHIM_CPU", "qemu64")


def rewrite(args):
    out = []
    i = 0
    while i < len(args):
        a = args[i]

        # -machine q35,accel=hvf  (Lima's form)
        if a.startswith("-machine") and i + 1 < len(args) and "accel=hvf" in args[i + 1]:
            out.append(a)
            out.append(args[i + 1].replace("accel=hvf", "accel=tcg"))
            i += 2
            continue

        # -accel hvf (standalone form). Preserve "help"/other probe values.
        if a == "-accel" and i + 1 < len(args):
            val = args[i + 1]
            out.append("-accel")
            out.append("tcg" if val == "hvf" else val)
            i += 2
            continue

        # -cpu host,... is invalid under TCG (host-only CPUID flags).
        if a == "-cpu" and i + 1 < len(args) and args[i + 1].startswith("host"):
            out.append("-cpu")
            out.append(TCG_CPU)
            i += 2
            continue

        out.append(a)
        i += 1
    return out


def main():
    if not os.path.isfile(REAL):
        sys.stderr.write(f"qemu-shim: real QEMU binary not found at {REAL}\n")
        sys.stderr.write("Set QEMU_SHIM_REAL or install via install.sh.\n")
        sys.exit(127)

    args = rewrite(sys.argv[1:])
    # Always inject the firmware directory so SeaBIOS/OVMF files are found.
    os.execv(REAL, [REAL, "-L", FIRMWARE_DIR] + args)


if __name__ == "__main__":
    main()
