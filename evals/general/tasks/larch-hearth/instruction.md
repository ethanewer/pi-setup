# TASK: larch-hearth — boot a tiny emulated Linux guest, mount a tool CD inside it, compile+run a static assembly program, write guest files to the host filesystem, and enable a no-password serial login.

You are inside one host container. Your job is to author a driver script
`/app/run.sh` (plus a main scenario `/app/scenario-main.json`) and run it so that
it produces the deliverables:

- `/app/run.sh` — a self-contained, executable bash driver (see the contract).
- `/app/guest.iso` — a tool CD (ISO9660) you assemble.
- `/app/serial.log` — the captured serial-console session of a live emulated guest.

The guest is a tiny Linux system you boot under the QEMU **software** emulator
(TCG — there is **no KVM**, no nested virtualisation). You must boot a real
kernel, attach your `guest.iso` as a CD-ROM, mount that CD device *inside the
guest*, copy its tool out and run it, compile and run a **statically-linked
inline-assembly program inside the guest** to an exact exit status, have the
guest write files to the **host filesystem** through the emulated shared
volume, and inject a custom init that sets up a **no-password serial login** so
a `login:` prompt appears on the console. Finally you leave the emulator running
as a background service.

## What the harness already provides in `/app`

- `/app/vmlinuz` — a prebuilt Linux kernel for the guest (x86_64, matches the
  host ABI). Do **not** modify it.
- `/app/base-initrd.cpio.gz` — a deliberately **trivial** busybox initramfs. It
  ships only busybox plus the decompressed kernel modules you will need
  (`isofs` for the CD-ROM, and `9pnet`, `9pnet_virtio`, `netfs`, `9p` for the
  shared host volume). Its default init merely mounts device nodes and drops to
  a shell — it does **not** enable login, does **not** mount any CD-ROM and does
  **not** set up the shared volume. You must **inject** a real init (see below).
  Do **not** modify this file either — copy it, add your injected init, and
  repack your own initramfs.
- A full C toolchain (`gcc`, `binutils`, glibc headers) in the host container.
- `qemu-system-x86_64`, `xorriso`, `isoinfo`, `cpio`, `zstd`, `gzip`,
  `busybox`, `python3`, `bash`.

## The intended mechanism (all genuinely inside the emulated guest)

Boot the guest with `-kernel /app/vmlinuz -initrd <your injected initramfs>` and
attach `guest.iso` as a CD-ROM with `-cdrom /app/guest.iso`. Share the **whole
host container root** into the guest with
`-virtfs local,path=/,mount_tag=hostroot,security_model=none`; after the guest
mounts it at `/hr`, it can `chroot` into the host root and use the container's
`gcc` to compile static programs (same x86_64 ABI, no KVM needed).

Your **injected init** (inside the initramfs you build from the base) must:

1. `mount -t proc proc /proc`, `mount -t sysfs sysfs /sys`,
   `mount -t devtmpfs devtmpfs /dev`.
2. `insmod` the bundled `isofs.ko`, then mount the CD-ROM device (`/dev/sr0`)
   at `/cd` (`mount -t iso9660 -o ro /dev/sr0 /cd`). Print the exact marker
   `LARCH_CDROM_MOUNT_OK` on success (or `LARCH_CDROM_MOUNT_FAIL`).
3. Run the tool that lives on the CD: it must print the exact marker
   `TOOL_RAN_OK`, and you must echo the CD manifest line to the console in the
   exact form `CD_MANIFEST=<payload>`.
4. `insmod` the bundled 9p modules (`9pnet`, `9pnet_virtio`, `netfs`, `9p`),
   then mount the shared host root:
   `mount -t 9p -o trans=virtio,version=9p2000.L hostroot /hr`. Print
   `LARCH_HOSTROOT_MOUNT_OK` on success. Copy the CD tool + manifest from `/cd`
   onto the shared host area (`/hr/opt/larch/work`) and print
   `LARCH_CDTOOL_COPIED`.
5. Run the in-guest work (your `/opt/larch/guest_work.sh`, reached via the
   host-root chroot — see below) and print a completion marker.
6. Print `LARCH_READY_FOR_LOGIN`, then hand the serial console to a
   **no-password login** (e.g. `exec setsid cttyhack /bin/login`) so a `login:`
   prompt appears on `ttyS0`. Provide a root account **and** your scenario's
   `login_user` account both with **empty passwords** in `/etc/passwd`, so
   logging in requires only the username (no password prompt).

### In-guest work (`/opt/larch/guest_work.sh`, run via chroot into the host root)

- Write a minimal C file whose `main` uses inline assembly to return exactly the
  scenario's `exit_status` (e.g. `int main(void){ int x; asm("movl $N,%0" :
  "=r"(x)); return x; }` with `N = exit_status`). Compile it **statically**
  (`gcc -static -O1 ...`) inside the guest, run it, capture its exit status, and
  print the exact marker `ASM_EXIT_STATUS=<that value>`. The marker value must
  **equal** the scenario's `exit_status`. When the static compile **succeeds**, print
  the exact marker `LARCH_COMPILE_OK` on the console before running the program.
- Write that same exit status to the shared host filesystem, e.g.
  `echo $? > /opt/larch/work/guest.prog.exit` (because `/opt/larch/work` lives
  on the 9p-shared host root, this is a guest syscall write that lands on the
  **host** filesystem, readable by the host after the guest finishes).

## QEMU launch requirements (inside `/app/run.sh`)

Boot the guest in the **background** (the emulator must keep running):

- `qemu-system-x86_64`, accelerator TCG only (`-accel tcg`, **no** `-enable-kvm`)
- `-kernel /app/vmlinuz -initrd <your injected initramfs>`
- `-append "console=ttyS0 panic=-1 rdinit=/init"`
- `-nographic -no-reboot`
- `-cdrom <OUTDIR>/guest.iso`
- `-virtfs local,path=/,mount_tag=hostroot,security_model=none`
- Serial console on a loopback TCP port:
  `-serial tcp:127.0.0.1:<serial_port>,server,nowait`
- Redirect qemu's own stderr/stdout to a log so it stays detached.

Drive the serial console programmatically: connect to the loopback port, wait
for the `login:` prompt, log in as the scenario's `login_user` (no password),
send `echo LARCH_AUTH_OK`, and capture the **entire** session (boot through
login) into `OUTDIR/serial.log`.

## The driver contract — `/app/run.sh`

`/app/run.sh [SCENARIO_JSON] [OUTDIR]`

- `SCENARIO_JSON` defaults to `/app/scenario-main.json`.
- `OUTDIR` defaults to `/app`.
- It must **generalize**: the harness will call it again on **hidden** scenarios
  (different `exit_status`, `payload`, `login_user`, `serial_port`), so it may
  not hard-code a single case. For every scenario it must rebuild `guest.iso`
  with that scenario's payload, rebuild the injected initramfs with that
  scenario's login user and exit status, boot the guest, and capture the serial
  session.

For any scenario `/app/run.sh` must:

1. Kill any previously running qemu so it can bind fresh ports.
2. Read the scenario (see schema), prepare `/opt/larch/guest_work.sh`
   (parameterized on exit status) and clear `/opt/larch/work`.
3. Assemble `OUTDIR/guest.iso` with `xorriso` (or `isoinfo`-compatible tools)
   starting from a build tree containing:
   - `toolkit/gadget.sh` — an executable shell tool that prints exactly
     `TOOL_RAN_OK` when run;
   - `toolkit/manifest.txt` — a file whose first line is exactly the scenario
     `payload` (no trailing spaces).
4. Build an initramfs by copying/extracting `/app/base-initrd.cpio.gz`, then
   injecting your custom init + `/etc/passwd` (root and `login_user`, both with
   empty password fields) + `/etc/group`. Repack it (cpio + gzip).
5. Boot the guest per the launch requirements above, in the background.
6. Drive the serial console to completion, capture `OUTDIR/serial.log`.
7. Copy the files the guest wrote to `/opt/larch/work` (e.g. `guest.prog.exit`,
   the copied CD tool/manifest) into `OUTDIR/` so the host can read them.
8. Leave qemu running in the background.

## Scenario JSON schema (create `/app/scenario-main.json`)

```json
{
  "name": "main",
  "exit_status": 21,
  "payload": "LARCH-HEARTH-MAIN-77",
  "login_user": "root",
  "serial_port": 55691
}
```

Limits the hidden cases stay inside: `exit_status` in `[1,255]`, `payload` is a
short `[A-Za-z0-9-]` string, `login_user` is a short alphanumeric name,
`serial_port` is a distinct loopback port in `55000..59999`.

`/app/run.sh` with no arguments must work using `/app/scenario-main.json` and
write the deliverables to `/app`: `/app/guest.iso`, `/app/serial.log`, plus it
must place `/app/guest.prog.exit` and the copied CD artifacts under `/app/`.

## Exact serial marker contract (the verifier greps for these)

Your captured `serial.log`, for each scenario, must contain:

- `LARCH_BOOT_OK`
- `LARCH_CDROM_MOUNT_OK` (CD-ROM mounted inside the guest)
- `TOOL_RAN_OK` (the CD tool ran)
- `CD_MANIFEST=<scenario-payload>` (manifest read from the mounted CD)
- `LARCH_HOSTROOT_MOUNT_OK` (9p shared host root mounted in the guest)
- `LARCH_CDTOOL_COPIED` (CD tool copied onto the shared host area)
- `LARCH_COMPILE_OK` (the in-guest static compile of the assembly program succeeded)
- `ASM_EXIT_STATUS=<scenario-exit-status>` (static program's real exit status)
- `LARCH_READY_FOR_LOGIN`
- a `login:` prompt, and `LARCH_AUTH_OK` after logging in as `login_user`
  without a password.

The host filesystem file `OUTDIR/guest.prog.exit` must contain exactly the
scenario's `exit_status`.

## What the verifier will do (satisfy it, don't rely on it)

It checks `/app/run.sh` is executable; verifies `/app/guest.iso` is a valid
ISO9660 image whose `toolkit/manifest.txt` first line equals the main scenario's
payload; verifies `/app/serial.log` contains all the markers above with the main
scenario's values; then re-runs `/app/run.sh` on 2-4 **hidden** scenarios into
per-case outdirs, and for each checks the rebuilt `guest.iso` payload, the
captured `serial.log` markers, the exact exit status, and the host-fs
`guest.prog.exit`. Pass requires every scenario to hold.

## Constraints & scoring

- Do **not** modify `/app/vmlinuz` or `/app/base-initrd.cpio.gz`.
- Do **not** shut qemu down at the end — the background emulator service is part
  of the task (the verifier re-probes the last scenario's serial socket).
- `/app/run.sh` must work with no arguments (using `/app/scenario-main.json`
  into `/app`) and with explicit scenario/outdir arguments.
- Create `/app/scenario-main.json`, run `/app/run.sh` to produce the
  deliverables in `/app`, and leave everything consistent.
