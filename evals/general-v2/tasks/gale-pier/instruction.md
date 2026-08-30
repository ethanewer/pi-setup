# Gale Pier platform bring-up

You are the sole operator of a platform bring-up lab. A bare host has been
shipped to you with tooling and a Linux **source tree**, but no kernel, no
guest OS, and no provisioning. Your job is to stand up a minimal Linux system
**from nothing** and leave behind the running machinery that the verifier will
re-execute.

Work entirely in `/app`. You never see `/tests` or `/solution` (they are not
mounted for you). Everything you produce must be runnable **again** by the
verifier in this same container, so the products below must be real programs
and the final states must be re-producible.

## Environment facts (already installed for you)

- Kernel source: `/usr/src/linux-source-6.8.0.tar.bz2` (Linux 6.8.0). Extract
  it under `/tmp` and compile — do **not** modify `/usr/src`.
- Static busybox binary: `/bin/busybox` (the distro's `busybox-static`). This
  is the only binary whose content hash the verifier will recognize as a valid
  core OS binary.
- Toolchain: `gcc`, `make`, `bc`, `flex`, `bison`, `libssl-dev`, `libelf-dev`,
  `cpio`, `gpg`, `qemu-system-x86_64` (QEMU 8.2, no KVM — plain TCG works).
- CPU/memory: several cores and ~4 GB; `nproc` reflects the quota.

## The deliverables (all in `/app`, all must exist)

| Path | Role |
|---|---|
| `/app/build-kernel.sh` | rebuilds a bootable kernel image |
| `/app/kernel/bzImage` | the built kernel image |
| `/app/provision.sh` | idempotent guest rootfs provisioner |
| `/app/rootfs/bin/busybox` | the guest's core OS binary |
| `/app/boot-qemu.sh` | boots the guest under QEMU, captures serial log |
| `/app/boot-serial.log` | the serial log with the operational marker |
| `/app/legacy/emulate.sh` | runs the legacy binary on the Pyxie emulator |
| `/app/legacy/output.txt` | the captured arithmetic output |

The verifier **executes each deliverable again**. `build-kernel.sh`,
`provision.sh`, `boot-qemu.sh` and `emulate.sh` must be executable, plain bash
(or a bash wrapper for `emulate.sh`), and must regenerate their outputs when
re-run.

## 1. Kernel build — `/app/build-kernel.sh`

The script must compile the shipped source into `/app/kernel/bzImage`:

- Extract `/usr/src/linux-source-6.8.0.tar.bz2` into a fresh work dir under
  `/tmp` (delete any previous extraction first — the verifier re-runs this
  script and expects a rebuild from clean sources).
- Configure with `make x86_64_defconfig`, then force at least these options
  **on** so the guest can actually boot over the serial console from an
  initramfs: `CONFIG_BLK_DEV_INITRD`, `CONFIG_RD_GZIP`, `CONFIG_DEVTMPFS`,
  `CONFIG_PROC_FS`, `CONFIG_SYSFS`, `CONFIG_TMPFS`, `CONFIG_SERIAL_8250`,
  `CONFIG_SERIAL_8250_CONSOLE`, `CONFIG_SERIAL_CORE_CONSOLE`,
  `CONFIG_BINFMT_ELF`. You may disable `CONFIG_MODULES` (this guest boots from
  initramfs and needs no modules) and you **must** disable `CONFIG_WERROR` —
  this Ubuntu-patched tree otherwise fails to build under GCC 13 with
  `-Werror=missing-prototypes`. Use `make olddefconfig` after toggling.
- Build with `make -j"$(nproc)" bzImage` (this takes a few minutes; do not
  race the timeout by using `-j1`).
- Copy `arch/x86/boot/bzImage` to `/app/kernel/bzImage`.

A correct build yields a ~12 MB kernel image. The verifier re-runs this script
and then boots the rebuilt image, so a misconfigured kernel (no serial console
or no initramfs support) will fail the boot stage.

## 2. Guest rootfs provisioning — `/app/provision.sh`

The script must (idempotently) create a busybox-based guest rootfs in
`/app/rootfs` (which already exists when the verifier runs — build on top of
it, never wipe it):

- `/app/rootfs/bin/busybox` must be **exactly one copy** of `/bin/busybox`
  (copy it in only if not already present). Its content hash must remain the
  recognized one: do not recompress, rebuild, patch, or replace it, and do not
  install any other busybox.
- Install the busybox applet symlinks so the guest has `/bin/sh`, `/bin/ls`,
  etc. (`/bin/busybox --install -s` from the rootfs works; it only adds
  missing links, so it is already idempotent).
- Account database (append new entries only when absent — never create a
  second user or group of the same name):
  - `/app/rootfs/etc/passwd` must contain `root` plus users
    **`bilge`** (UID 1001) and **`halyard`** (UID 1002), each with
    `/bin/sh` as shell and a home dir under `/home`.
  - `/app/rootfs/etc/group` must contain **`spinnaker`** (GID 1000) with both
    `bilge` and `halyard` as members.
  - `/app/rootfs/etc/shadow` must carry a line for each of the three accounts.
  - Home directories `/home/bilge`, `/home/halyard`, `/root` must exist.
- Guest boot scripts (must be present and executable):
  - `/app/rootfs/etc/fstab` — mount `proc` and `sysfs`.
  - `/app/rootfs/init` — the initramfs entry point. It must mount `proc`,
    `sysfs` and `devtmpfs` (`/dev`), then print on the serial console the
    exact line

    ```
    === GALE-PIER-GUEST-OPERATIONAL ===
    ```

    and then keep an interactive busybox shell alive on the serial console
    (e.g. a loop respawning `/bin/sh -i` on `/dev/ttyS0`). The marker line and
    a `built-in shell` banner must therefore appear in the boot log.

**Idempotency contract (checked by the verifier):** the verifier runs
`/app/provision.sh` twice on top of your state. After every run there must be
**exactly one** entry for `bilge`, exactly one for `halyard`, exactly one
`spinnaker` group, and exactly one busybox binary. No duplicate lines, no
duplicate UIDs, nothing that grows with re-runs.

## 3. QEMU boot — `/app/boot-qemu.sh`

The script must pack `/app/rootfs` into a gzip'd cpio initramfs
(`(cd /app/rootfs && find . | cpio -o -H newc | gzip -9)`) and boot it with the
built kernel:

```
qemu-system-x86_64 -m 256 -kernel /app/kernel/bzImage -initrd /app/rootfs.cpio.gz \
  -append "console=ttyS0" -nographic -no-reboot
```

- Capture the full serial output to `/app/boot-serial.log` (overwrite it each
  run; remove any stale copy first).
- Booting takes a couple of seconds on this image; the marker appears quickly.
  Exit 0 as soon as `=== GALE-PIER-GUEST-OPERATIONAL ===` appears in the log
  (bounded watchdog, e.g. 2 minutes, with `timeout --signal=KILL` around QEMU
  so a broken kernel does not hang forever). Exit non-zero if the marker never
  appears.
- QEMU runs fine without KVM (TCG). Do not pass `-enable-kvm`.

The verifier re-runs this script and needs the marker **and** the busybox
`built-in shell` banner inside `/app/boot-serial.log`.

## 4. Legacy execution — the Pyxie console

`/app/legacy/legacy.bin` is a bare binary for the **Pyxie console**, a
fictional 16-register machine. It must be executed under a software emulator
you write — nothing in `/app` can run it natively.

### Pyxie machine contract

- A program is a sequence of 8-byte instructions, little-endian.
- Instruction layout:
  - byte 0: opcode
  - byte 1: register `D` (lower 4 bits used)
  - byte 2: register `A` (lower 4 bits)
  - byte 3: register `B` (lower 4 bits)
  - bytes 4–7: signed 32-bit immediate, two's complement, little-endian
- Registers `r0..r15` start at 0. All arithmetic is on **signed 32-bit
  two's-complement** values and wraps on overflow (e.g. `2000000000 +
  2000000000 = -294967296`, `2147483647 + 2147483647 = -2`).
- Opcodes:
  | byte | mnemonic | semantics |
  |---|---|---|
  | `0x11` | `LD`  | `rD = imm` |
  | `0x21` | `ADD` | `rD = rA + rB` (wrap) |
  | `0x22` | `SUB` | `rD = rA - rB` (wrap) |
  | `0x23` | `MUL` | `rD = rA * rB` (wrap) |
  | `0x30` | `PRT` | print the decimal value of `rA`, **one value per line** |
  | `0xFF` | `HALT` | stop immediately; all later bytes are ignored |
- **Edge cases the verifier's hidden binaries will probe (handle all):**
  - An instruction whose opcode byte is not one of the above is **ignored**
    and execution continues with the next instruction.
  - If the file ends with a partial (truncated) final record that is not a
    full 8 bytes, that trailing fragment is **ignored**; the program just
    ends there. The emulator must not crash on short input.
  - A program that never reaches `HALT` runs to the end of the file.
  - `PRT` prints exactly `%d\n` per value, in program order, even when the
    value is negative. A program with no `PRT` (or an empty input file)
    produces an **empty output file**.

### `/app/legacy/emulate.sh`

CLI contract (this is what the verifier calls, including with hidden inputs):

```
/app/legacy/emulate.sh [INPUT.bin [OUTPUT.txt]]
```

- No args: read `/app/legacy/legacy.bin`, write `/app/legacy/output.txt`.
- One arg: read that file, write `/app/legacy/output.txt`.
- Two args: read the first, write the second.
- Exit 0 on success and overwrite the output file each run (stale copies must
  not survive). Behave correctly for the edge cases above (a malformed input
  still yields the deterministic documented output and exit 0).

You may implement the interpreter as a Python 3 program (e.g.
`/app/legacy/pyxie.py`) that `emulate.sh` invokes — or as anything else you
like, as long as the CLI contract holds. The verifier independently decodes
the same documented format and compares the text it gets from your emulator
against its own computed output, for the shipped binary **and** for hidden
binaries that exercise the edge cases.

## General rules

- All four scripts must be `chmod +x` and runnable from a bare `bash path`
  invocation inside this container.
- Do not use the network at any point; the whole lab is offline.
- Do not delete or overwrite files outside the deliverables you own (leave
  `/usr/src`, `/bin/busybox`, the QEMU install, etc. untouched).
- The verifier runs everything single-shot in this container: kernel rebuild
  → guest boot → provision double-run → legacy runs. Plan for the total
  rebuild time (the kernel build dominates — a few minutes) so nothing
  soft-fails on output buffering or premature exits.
- If in doubt about a path or name, the exact strings above are the contract:
  the verifier greps `/app/boot-serial.log` for `=== GALE-PIER-GUEST-OPERATIONAL ===`
  and for `built-in shell`, and it matches account/group names `bilge`,
  `halyard`, `spinnaker` exactly.