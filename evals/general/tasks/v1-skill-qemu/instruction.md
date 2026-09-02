# QEMU VM launch command

You must produce a QEMU command line that launches a virtual machine whose configuration is described in `/app/vm_spec.txt` (simple `KEY=VALUE` lines):

- `RAM_MiB=8192`  → the VM should be given 8192 MiB of RAM
- `VCPUS=4`       → the VM should have 4 virtual CPUs
- `DISK_IMAGE=/app/guest.img` → the guest boots from this raw disk image
- `DISPLAY=none`  → run headless

Write `/app/qemu_cmd.txt` containing a **single line** that starts with `qemu-system-x86_64` — a complete, runnable-looking QEMU invocation that reflects these settings.

It must include (as standalone flag=value tokens):
- the RAM flag `-m 8192` (MiB, matching the spec)
- the vCPU flag `-smp 4`
- a drive flag whose `file=` points to `/app/guest.img` with `format=raw`
- a `-display none` flag

Use the exact numbers from the spec (8192 and 4). Do not add a trailing blank line.
