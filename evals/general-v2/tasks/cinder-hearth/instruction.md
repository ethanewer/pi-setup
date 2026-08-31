# cinder-hearth — inject an init that enables unauthenticated serial login

You are bringing up a fleet-boot image for the **Cinder Harbor lighters**. A
tiny Linux guest boots under the QEMU **software** emulator (TCG — there is
**no** KVM) from a prebuilt kernel and a deliberately trivial base initramfs.
The base init does not mount the pseudo-filesystems, does not create any
accounts, and does not start any getty: an operator at the serial console
currently gets nothing useful. Your job is to **inject a real init** that
mounts the pseudo-filesystems, unpacks the mission seed, sets up an
**unauthenticated** account, and hands the serial console to a login prompt —
then boot it and drive a full login session programmatically.

You are in `/app`. The harness provides (do **not** modify either):

- `/app/vmlinuz` — prebuilt x86_64 Linux kernel for the guest.
- `/app/base-initrd.cpio.gz` — trivial busybox initramfs (busybox applets in
  `/bin`, no `/etc/passwd`, no getty/login, init only prints
  `CINDER_BASE_INIT` and execs a shell).

## Deliverables (all four required)

1. `/app/mkinit.sh` — executable; builds the injected initramfs:
   ```
   bash /app/mkinit.sh <scenario.json> <out_initrd>
   ```
2. `/app/console_drive.py` — executable; boots the guest and drives the
   serial login:
   ```
   python3 /app/console_drive.py <initrd> <scenario.json> <out_log>
   ```
3. `/app/guest-initrd.cpio.gz` — the injected initramfs for the **main**
   scenario `/app/scenario-main.json`.
4. `/app/session.log` — the captured serial session (boot through successful
   login) for the **main** scenario.

Also create `/app/scenario-main.json` for the main scenario:

```json
{
  "name": "main",
  "user": "deckhand",
  "token": "CINDER-HEARTH-MAIN-412",
  "serial_port": 56123
}
```

## `/app/mkinit.sh` contract

For any scenario `{"name":..., "user":..., "token":..., "serial_port":...}`:

1. Extract `/app/base-initrd.cpio.gz` to a temp tree (`gzip -dc | cpio -idm`).
2. Write an injected `/init` that:
   - mounts the pseudo-filesystems: `mount -t proc proc /proc`,
     `mount -t sysfs sysfs /sys`, `mount -t devtmpfs devtmpfs /dev`, and only
     then prints `CINDER_BOOT_OK` and `CINDER_PSEUDOFS_OK`;
   - prints `CINDER_SEED_TOKEN=<token>` where `<token>` is read from a
     `/seed/token.txt` file **embedded in the initramfs** containing exactly
     the scenario token;
   - prints `CINDER_SERIAL_TTY=ttyS0`;
   - prints `CINDER_READY_FOR_LOGIN`;
   - finally hands the **serial console** to a login prompt, e.g.
     `exec setsid cttyhack /bin/login` (or a getty on `ttyS0`).
3. Inject `/etc/passwd` and `/etc/group` with a `root` entry **and** the
   scenario `user` entry, both with **empty password fields** (so login
   requires only the username — an unauthenticated account), and a home
   directory for `user`.
4. Repack the tree (`find . | cpio -o -H newc | gzip`) to `<out_initrd>`.

The injected init script (as a file inside the produced initramfs) must
literally reference the pseudo-fs mounts (`proc`, `sysfs`, `devtmpfs`),
`ttyS0`, and the login/getty handoff — the grader extracts and inspects it.

## `/app/console_drive.py` contract

For any `<initrd>` + scenario + `<out_log>`:

1. Kill any stale `qemu-system` processes so the port is free.
2. Boot in the background:
   ```
   qemu-system-x86_64 -accel tcg -kernel /app/vmlinuz -initrd <initrd> \
     -append "console=ttyS0 panic=-1 rdinit=/init" -m 256M -no-reboot \
     -display none -serial tcp:127.0.0.1:<serial_port>,server,nowait
   ```
   (TCG only — never `-enable-kvm`.) Leave the emulator running when the
   script exits.
3. Connect to the loopback serial TCP port, wait for the `login:` prompt
   (allow minutes — software emulation is slow), send the scenario `user`
   followed by Enter. No password must be needed; if a `Password:` prompt
   appears anyway, respond with an empty line.
4. After the shell comes up, send `echo CINDER_AUTH_OK` and wait until
   `CINDER_AUTH_OK` appears on the console.
5. Write the **entire captured session** (boot through login) to `<out_log>`
   and exit 0. On timeout/connection failure exit non-zero.

## Exact marker contract (the grader greps the captured log)

For each scenario the captured session log must contain, in order:

- `CINDER_BOOT_OK`
- `CINDER_PSEUDOFS_OK`
- `CINDER_SEED_TOKEN=<scenario token>` (read from the embedded seed file)
- `CINDER_SERIAL_TTY=ttyS0`
- `CINDER_READY_FOR_LOGIN`
- a `login:` prompt
- `CINDER_AUTH_OK` (after logging in as the scenario user, no password)

## What the grader will do

It runs `mkinit.sh` + `console_drive.py` for the main scenario and for 3
hidden scenarios (different `user`, `token`, `serial_port`), and for each:

- validates the full marker chain above in the captured `session.log`;
- extracts the injected initramfs and checks the init script text (pseudo-fs
  mounts, `ttyS0`, login/getty handoff), the `/etc/passwd` empty password
  fields for `root` and the scenario user, and the embedded
  `/seed/token.txt` content;
- requires `console_drive.py` to leave the emulator running (background
  service).

Pass requires every scenario to hold.

## Constraints

- Do **not** modify `/app/vmlinuz` or `/app/base-initrd.cpio.gz`.
- `mkinit.sh` and `console_drive.py` must generalize — no scenario values
  (user, token, port) may be hard-coded.
- Offline, single container; TCG emulation only.
