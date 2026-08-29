# Brisk Jetty — enroll an emulated "Nysa relay appliance" over its serial console and prove a live network fetch

Coastal Nysa runs a small fleet of "relay appliances" that speak only to the local
loopback of their host. These appliances are Linux guests **emulated in software**
(there is **no `/dev/kvm`**, so QEMU must run with TCG, e.g. `-machine pc,accel=tcg`).
Each appliance is shipped **unenrolled**: its sshd and its tiny *relay control
panel* are disabled until a root operator sits at the serial console of the device
and completes the first-run configuration. After enrollment the appliance is only
reachable through host ports forwarded into the guest, and a broken host name
mapping must be repaired so a live fetch of the appliance's page really works.

Your job is to stand up one such appliance for real, automate its first-run
serial-console configuration, prove host→guest ssh, repair the host network path,
and capture a genuine live fetch of the appliance's page.

You are root inside a Ubuntu 24.04 container, working at `/app`. There is no
internet at runtime; everything you need is already installed.

## What the harness already provides

- `/opt/gk/vmlinuz` — a bootable distro kernel for guests.
- `/opt/gk/guest-initrd.cpio.gz` — the **guest OS image** (a distro-less
  busybox+dropbear Linux system) provisioned by the supplied fixture
  `/opt/gk/mkguest.sh`. **Do not modify or rebuild this guest OS.**
- `/opt/gk/mkguest.sh` — the fixture that builds the guest OS (for reference).
- `qemu-system-x86_64`, `qemu-img` — emulation and disk-image tooling.
- `dropbear`, `dropbearkey`, `busybox` — guest-side tools (baked into the guest
  OS by the fixture).
- `ssh`, `sshpass`, `python3`, `getent` — host-side tools.
- `/app` is empty.

### How the guest behaves (read carefully)

The supplied guest OS boots to a **serial login console**. It brings up `eth0`
(static `10.0.2.15/24`, gateway `10.0.2.2`), prints a small banner, and then prompts
`nysa login:` **on the serial console** — because it is *unenrolled*, nothing
(no sshd, no relay) is listening until a root operator configures it. Inside the
guest:

- `root` logs in with password `kestrel-mistral-1987` (prompt then `Password:`).
- The appliance hostname must be set to **`nysa-relay-appliance`**.
- Running **`enroll`** (an in-guest command) as root:
  1. generates a fresh per-boot **relay token** (random hex from `/dev/urandom`);
  2. writes `enrolled=yes hostname=<hostname> token=<token>` to `/etc/rc/enroll`;
  3. writes the live page `RELAY-LIVE kestrel <token>` at `/var/www/relay/live`;
  4. starts the **ssh server** (dropbear) on guest port **22**;
  5. starts the **relay control panel** (busybox httpd) on guest port **3733**,
     which serves the page at path `/live`.

The token is regenerated on **every** boot, so the page an appliance serves is
*per-boot random* — the only faithful copy of it is obtained by actually fetching
over the live network path.

## Your deliverables (in `/app`)

| `/app` file | what it must be |
|---|---|
| `run_guest.sh` | executable bring-up driver (contract below) |
| `guest.qcow2` | a valid `qcow2` image the running VM is attached to |
| `guest_daemon.pid` | PID of the daemonized QEMU process |
| `guest_console.log` | the serial console transcript, showing the **interactive** first-run steps were actually typed |
| `ssh_host_exec.sh` | executable ssh executor into the guest (contract below) |
| `fetch.py` | executable fetcher (contract below) |
| `fetch_result.html` | the exact bytes of a **live** fetch of the appliance page over the repaired host path |

Produce all of them by doing the work: write `run_guest.sh`, `ssh_host_exec.sh`
and `fetch.py`, then **run** them so the standing deliverables exist.

## `/app/run_guest.sh` contract

Executable bash with this behaviour:

```
bash /app/run_guest.sh          # ensure the guest is up (idempotent)
bash /app/run_guest.sh STATUS   # print state; exit 0 iff the ssh forward is reachable
bash /app/run_guest.sh STOP     # tear the guest down
```

First invocation must:

1. Create `/app/guest.qcow2` (e.g. `qemu-img create -f qcow2 ... 64M`) and attach
   it to the VM as its disk.
2. Boot the supplied guest OS headless under software emulation:
   `qemu-system-x86_64 -machine pc,accel=tcg ...` with the kernel
   `/opt/gk/vmlinuz` and initrd `/opt/gk/guest-initrd.cpio.gz`.
3. Put the serial console on a **unix socket** (e.g.
   `-chardev socket,path=/tmp/nysa-console.sock,server=on,wait=off`) and capture
   the full transcript to **`/app/guest_console.log`** (qemu chardev `logfile=`
   is a clean way; recording everything from your driver works too).
4. Configure QEMU **user-mode networking** with these two host forwards:
   `hostfwd=tcp:127.0.0.1:61234-:22` (host port **61234** → guest ssh **22**) and
   `hostfwd=tcp:127.0.0.1:18080-:3733` (host port **18080** → guest relay **3733**),
   using `-device virtio-net-pci`.
5. **Drive the serial console non-interactively** — type the first-run steps into
   the socket as if an operator were at the terminal:
   - wait for `login:`, send `root`;
   - wait for `Password:`, send `kestrel-mistral-1987`;
   - wait for the root `#` prompt;
   - set the hostname (`hostname nysa-relay-appliance` and persist it, e.g.
     `echo nysa-relay-appliance > /etc/hostname`);
   - run `enroll` and wait until the guest reports `NYSA-READY`.
6. Leave the emulator running as a **daemonized background** process that survives
   this script exiting (e.g. `qemu ... -daemonize -pidfile /app/guest_daemon.pid`).
7. Return exit 0 only when the guest is up and the forwarded ssh port answers.

**Idempotency:** if a daemonized guest with these forwards is **already running
and reachable**, a fresh `bash /app/run_guest.sh` must detect that, **not spawn a
second VM**, and return quickly (exit 0). This is probed at validation time.

## `/app/ssh_host_exec.sh` contract

Executable bash:

```
bash /app/ssh_host_exec.sh "<remote command...>"
```

Runs the given remote command **inside the guest** over the forwarded ssh port
(`127.0.0.1:61234`, authenticating as root with the appliance password) and
prints its stdout. With **no argument** it must print a usage line to stderr and
return **non-zero**.

## `/app/fetch.py` contract

Executable, callable as `python3 /app/fetch.py URL [OUTFILE]`:

- Fetches `URL` and writes the exact response bytes to `OUTFILE` (default
  `/app/fetch_result.html`).
- On a **dead/unreachable URL or failure**, it must exit non-zero and **must not
  create, truncate, or modify the output file** in any way (write the file only
  after a successful fetch).
- It must work for any reachable `http://` URL, not just the canned relay page.

## The network repair and the live fetch

`nysa.test` is the appliance's DNS name for its host loopback. Host name
resolution for it is **broken**: `/etc/hosts` has **no** `nysa.test` entry, so
`http://nysa.test:18080/live` cannot resolve (the fetch fails). Repair the host
network path so the appliance's page is genuinely reachable:

1. Fix `/etc/hosts` — add the correct loopback mapping so `nysa.test` resolves to
   `127.0.0.1` (e.g. append `127.0.0.1 nysa.test`).
2. Confirm `getent hosts nysa.test` returns `127.0.0.1`.
3. Use **your** `fetch.py` to fetch `http://nysa.test:18080/live` into
   `/app/fetch_result.html`. This must go over the real network path:
   host → `127.0.0.1:18080` → qemu user-net → guest relay panel → the live
   per-boot page `RELAY-LIVE kestrel <token>`.

`fetch_result.html` must be the **live** page: it must contain
`RELAY-LIVE kestrel <token>` and byte-for-byte equal whatever a fresh live fetch
of `http://nysa.test:18080/live` returns **right now** while the guest is running.
A static/fabricated snapshot (e.g. a hard-coded string, or bytes copied before
the real path works) will not match.

## What is validated at the end

The verifier runs after you finish, while the daemonized guest and the repaired
`/etc/hosts` are still in place. Independently of your implementation it checks:

- host→guest ssh reachability by connecting to `127.0.0.1:61234` and reading an
  `SSH-2.0-` banner;
- that the recorded daemon PID is alive and is the QEMU process configured with
  both forwards, and that `/app/guest.qcow2` is a valid qcow2 image attached to it;
- that `/app/guest_console.log` shows the interactive first-run steps were issued
  (`login:`, the typed hostname and `enroll`, and `NYSA-READY`), and that the
  console-log enroll token matches the token of the running service;
- that the relay panel is reachable on `127.0.0.1:18080` and serves
  `RELAY-LIVE kestrel <token>`;
- that `/etc/hosts` was repaired (`nysa.test` → `127.0.0.1`);
- that `/app/ssh_host_exec.sh` genuinely runs a command in the guest;
- that `/app/fetch_result.html` is byte-identical to a fresh live fetch of the
  relay page and carries that page's live token;
- hidden scenarios that re-execute your deliverables on new inputs: a dead-URL
  fetch must fail cleanly without touching its output file, `ssh_host_exec.sh`
  must print usage and return non-zero with no argument, re-running `run_guest.sh`
  must be idempotent (no duplicate emulator), and `fetch.py` must fetch an
  arbitrary different reachable URL exactly.

## Constraints

- Software emulation only (`-accel tcg`); there is no `/dev/kvm`.
- The guest emulator must **stay alive** after your scripts return (background
  service) — do not tear it down.
- Do not modify `/opt/gk/guest-initrd.cpio.gz`, `/opt/gk/vmlinuz`, or the guest OS
  fixture; the unenrolled first-run behaviour is part of the task.
- Do not modify anything under `/tests` (read-only for you anyway).
- Work in `/app`; do not rely on hidden fixtures.

## Remember

- Produce every deliverable by running your own scripts (`run_guest.sh`,
  `ssh_host_exec.sh`, `fetch.py`), not by copying answer content.
- The appliance must actually be reachable via forwarded ssh *after* your session
  ends, and `fetch_result.html` must be the live page from the running guest over
  the repaired host path.
