# QEMU 5.2 guest provisioning command

Produce a QEMU command line for a machine specified in `/app/qemu_spec.txt` (`KEY=VALUE` lines):

- `RAM_MiB=2048` → 2048 MiB RAM
- `VCPUS=2` → 2 virtual CPUs
- `BOOT_MEDIA=/app/guest.iso` → an ISO install/guest media image
- `BOOT_ORDER=cd` → boot first from the (optical / CD-ROM) media, then other devices

Write `/app/qemu_boot.txt` containing one line starting with `qemu-system-x86_64` with:
- `-m 2048`
- `-smp 2`
- a drive for the ISO attached as an optical media device: the drive token `file=/app/guest.iso` together with `media=cdrom`
- a `-boot` flag reflecting boot priorities from the CD-ROM first (e.g. `-boot order=cd` or `-boot c`-style ordering)

Use the exact RAM and VCPU numbers from the spec (2048 and 2).
