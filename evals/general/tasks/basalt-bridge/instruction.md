# Basalt Bridge — headless guest service on a loop port forward

Waverfield runs a small "basalt-bridge" relay: a guest Linux service is emulated in
software (there is **no `/dev/kvm`**, so QEMU must run with TCG `-accel tcg`), only
reachable on a forwarded host loopback port, and kept alive as a background service.
A port of the relayer's client tooling (`curl`) has also been broken and must be
repaired so a live fetch returns the exact original remote bytes. Your job is to
produce two reusable scripts that do this real work, and to run them so the standing
deliverables exist in `/app`.

You are inside a Ubuntu 24.04 container running as root at `/app`. All tools are
already installed; there is no internet at runtime.

## What is already in the workspace

- `/opt/gk/vmlinuz` — a bootable distro kernel for guests.
- `/opt/gk/busybox` — a **static** busybox to build a minimal guest userland.
- `/opt/gk/modules/*.ko` — decompressed virtio driver modules for that kernel
  (`virtio.ko`, `virtio_ring.ko`, `virtio_pci.ko`, `virtio_net.ko`). The guest needs
  these to bring up its network device.
- `dropbear`, `dropbearkey` — a real SSH server you embed in the guest.
- `qemu-system-x86_64`, `qemu-img` — emulation and disk-image tooling.
- `/usr/bin/curl` is **broken**: it is a stub script (exit code 7) until you repair
  it. A pristine native `curl` binary is kept at **`/opt/gk/curl.orig`**.
- `/app/origin/` — the "true remote" mirror content that a real curl must fetch
  back, in particular `/app/origin/basalt-bridge.html` (served over loopback by a
  small HTTP server you stand up).

## The scenario contract

1. The final deliverable set (everything in `/app`):

   | `/app` file | what it must be |
   |---|---|
   | `run_guest.sh` | executable script that stands the guest up (see contract below) |
   | `guest.qcow2` | a valid `qcow2` disk image the running VM is attached to |
   | `forward_check.log` | log produced by the guest bring-up that records a **live** host→guest reach probe |
   | `guest_daemon.pid` | the PID of the daemonized QEMU process |
   | `restore_curl.sh` | executable script that repairs `/usr/bin/curl` and captures a live fetch |
   | `fetch_result.html` | the exact bytes a real `curl` returned from the loopback mirror |

## `/app/run_guest.sh` contract

A bash script, executable (`chmod +x`), with this behaviour:

```
bash /app/run_guest.sh          # ensure the guest is up (idempotent)
bash /app/run_guest.sh STATUS   # print state; exit 0 iff forwarded & reachable
bash /app/run_guest.sh STOP     # tear the guest down
```

First invocation must:

- Create `guest.qcow2` (e.g. `qemu-img create -f qcow2 ... 64M`) and pass it to the
  VM as its disk.
- Build a minimal guest root (initial ramdisk) from `/opt/gk/busybox` + a `dropbear`
  SSH server, including the virtio driver modules so the guest NIC can come up.
- Boot it headless under **software emulation**:
  `qemu-system-x86_64 -machine pc,accel=tcg ...` with QEMU **user-mode networking**:
  `-netdev user,id=n0,hostfwd=tcp:127.0.0.1:3134-:22 -device virtio-net-pci,netdev=n0`
  so a host connection to `127.0.0.1:3134` reaches the guest's sshd on port 22.
- The guest must bring up `eth0` (static `10.0.2.15/24`, default gateway `10.0.2.2`)
  and run the SSH server (dropbear) on port 22.
- Leave the emulator running as a **background daemon** that survives the script's
  exit: use `qemu -daemonize -pidfile /app/guest_daemon.pid`. It must be alive again
  later, after the launching session has ended.
- Write a host→guest reachability probe to `/app/forward_check.log`. It must contain
  `status=OPEN` and the SSH banner read by actually connecting to the forwarded port
  (a line beginning `SSH-2.0-`).

Idempotency: if a daemonized guest with the forwarding is **already running and
reachable**, a fresh `bash /app/run_guest.sh` must detect that, **not spawn a second
VM**, and return quickly (still exit 0). This is probed at validation time — do not
break your own service by re-running the script.

## `/app/restore_curl.sh` contract

A bash script, executable, with this behaviour:

```
bash /app/restore_curl.sh
```

It must:

1. Make `/usr/bin/curl` a **bona fide native executable** — an ELF binary with the
   executable bit set (not a script, not chmod-000). The pristine binary at
   `/opt/gk/curl.orig` may be laid back onto `/usr/bin/curl`.
2. Ensure a loopback HTTP mirror serving the true remote content is running, rooted
   at `/app/origin` (stand it up yourself, e.g. `python3 -m http.server` bound to
   `127.0.0.1`).
3. Use the restored `/usr/bin/curl` to fetch
   `http://127.0.0.1:<port>/basalt-bridge.html` and save the exact bytes to
   `/app/fetch_result.html`. `fetch_result.html` must byte-for-byte equal
   `/app/origin/basalt-bridge.html`.

It must be safe to run repeatedly (idempotent) and tolerate being handed stray/malformed
arguments without breaking.

## What is validated at the end

The verifier runs after you finish, while the guest mirror and daemonized QEMU you
started are still alive. Independently of how you implemented it, it checks:

- host→guest SSH reachability by connecting to `127.0.0.1:3134` and reading an
  `SSH-2.0-` banner;
- the daemonized guest pid from `/app/guest_daemon.pid` is alive and is a QEMU
  process configured with that forwarding;
- `/app/forward_check.log` contains `status=OPEN` and an `SSH-2.0-` banner;
- `/app/guest.qcow2` is a valid qcow2 image;
- `/usr/bin/curl` is a genuine ELF executable that reports its curl identity;
- `/app/fetch_result.html` equals the true remote bytes;
- a live loopback fetch returns those same true bytes;
- re-running `restore_curl.sh` (with stray args) and re-running `run_guest.sh` stay
  safe: the forwarded guest service must remain reachable, the daemon pid must not
  drift to a duplicate, and a restored curl must fetch another (different) URL as
  well, not just the one canned page.

## Constraints

- Run everything with QEMU software emulation (`-accel tcg`); there is no `/dev/kvm`.
- The guest emulator must **stay alive** after your scripts return (background service).
- Do not modify anything under `/tests` (it is mounted read-only for you anyway).
- Work in `/app`; place all six deliverables there. Do not rely on hidden fixtures.

## Remember

- Produce all six deliverables by running your own scripts (`run_guest.sh` then
  `restore_curl.sh`), not by copying answer content.
- The guest must actually reach sshd over the forwarded port *after* your launching
  session ends, and `/usr/bin/curl` must be a real, working executable.