# slate-hollow — build a rescue appliance with a passwordless serial login

You are packaging a **rescue appliance**: a tiny Linux guest that boots under
QEMU (software emulation, TCG — no KVM) and offers a login prompt on its
**serial console**. The harness ships a prebuilt kernel and a deliberately
trivial base initramfs; you must inject a real init, repack the appliance, and
prove the login works end to end.

## What the harness provides in `/app`

- `/app/vmlinuz` — prebuilt x86_64 Linux kernel. **Do not modify.**
- `/app/base.cpio.gz` — trivial busybox initramfs (`/bin/busybox`, applet
  symlinks, device nodes `/dev/console`, `/dev/null`, `/dev/ttyS0`, `/dev/tty`,
  and a do-nothing `/init` that only mounts devtmpfs and drops to a shell). It
  does **not** mount proc/sysfs, has **no** user accounts, and starts **no**
  getty. **Do not modify** — copy it, inject, repack your own initramfs.
- Host tools: `qemu-system-x86_64`, `busybox`, `cpio`, `gzip`, `python3`,
  `bash`, a full toolchain.

## Deliverables (all four required)

1. **`/app/mkinit.sh`** — executable bash script:
   ```
   bash /app/mkinit.sh <USERNAME> <OUTDIR>
   ```
   Builds `<OUTDIR>/appliance.cpio.gz`: a gzip'd newc cpio initramfs starting
   from `/app/base.cpio.gz` with the injected `/init`. `<USERNAME>` matches
   `^[a-z_][a-z0-9_-]{0,15}$` and may be **any** such name (the verifier uses
   names you have never seen), so nothing may be hard-coded to one user.
2. **`/app/appliance.cpio.gz`** — the artifact produced by
   `bash /app/mkinit.sh rescue /app` (visible user `rescue`).
3. **`/app/drive.sh`** — executable bash script:
   ```
   bash /app/drive.sh <APPLIANCE_CPIOGZ> <USERNAME> <OUTDIR>
   ```
   Boots that appliance under `qemu-system-x86_64` (TCG: `-accel tcg`, no
   KVM; `-kernel /app/vmlinuz -initrd <APPLIANCE>`; serial console with
   `-append "console=ttyS0 rdinit=/init panic=-1"` and
   `-display none -monitor none -serial stdio -no-reboot`), waits for the
   `login:` prompt, logs in as `<USERNAME>` **with no password**, sends
   `echo RESCUE_LOGIN_OK`, and captures the **entire** session (boot through
   the post-login command) into `<OUTDIR>/console.log`. Exit 0 iff the login
   succeeded. It must terminate the emulator before exiting and must work for
   any valid `<USERNAME>`/appliance pair.
4. **`/app/console.log`** — produced by
   `bash /app/drive.sh /app/appliance.cpio.gz rescue /app`.

## The injected init — exact contract (inside the guest)

Your `/init` (inside every appliance you build) must:

1. Mount the pseudo-filesystems: `proc` at `/proc`, `sysfs` at `/sys`,
   `devtmpfs` at `/dev`.
2. Print the exact marker `RESCUE_APPLIANCE_READY` on the console.
3. Set up an **unauthenticated account** for `<USERNAME>`: uid `1000`, empty
   password (busybox `login` requires no password when the password field is
   empty), home directory `/home/<USERNAME>` (create it), shell `/bin/sh`.
4. Start a `getty` on the **serial** console `ttyS0` (e.g. busybox
   `getty -L ttyS0 115200 vt100`) so a `login:` prompt appears; a valid
   username at the prompt must yield a working shell without any password.

## What the verifier does

- Checks the deliverables exist (scripts executable) and that `/app/vmlinuz`
  and `/app/base.cpio.gz` are unmodified.
- Checks `/app/console.log` contains `RESCUE_APPLIANCE_READY`, a `login:`
  prompt and `RESCUE_LOGIN_OK`.
- **Independently boots** `/app/appliance.cpio.gz` with its own serial driver,
  logs in as `rescue`, and inside the guest verifies: the pseudo-filesystems
  are mounted (`cat /proc/mounts` shows `proc`, `sysfs`, `devtmpfs`), and
  `id -u` = `1000`, `id -un` = `rescue`.
- For **hidden users** you have not seen, it runs
  `bash /app/mkinit.sh <user> <tmpdir>` and repeats the independent boot and
  in-guest checks for each. All cases must pass.
