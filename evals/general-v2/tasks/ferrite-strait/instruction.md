# Ferrite wall-kiosk appliance (provisioning stage)

You are provisioning the **Ferrite** wall-mounted kiosk appliance inside this
container. The appliance's emulated machine must be brought up **without a
GPU, X server, KVM, systemd, or any networking**, kept running in the
background, and made remotely observable through **VNC on display :1** and a
**monitoring web plane on the standard web port (80)** — including a **live
status endpoint** that always reflects the actually-running VM.

This is the firmware-provisioning stage: the guest has no OS payload yet and
boots its firmware only (no `-kernel`); the emulated machine simply has to
stay up with its display exposed. Everything (qemu, busybox) is already
installed in the container.

Work only under `/app` (plus `/tmp` as scratch). Create exactly three
deliverables:

- `/app/launch.sh`  — the launcher that brings the kiosk up and keeps it
                      running (executable)
- `/app/kiosk.conf` — the runtime config the launcher reads by default
- `/app/status.cgi` — the live-status program the launcher installs into the
                      web plane as the `/cgi-bin/status.json` endpoint

## Part 1 — the runtime config

`/app/kiosk.conf` is the **default config**, a JSON file with exactly these
fields:

```json
{
  "vnc_display": 1,
  "web_port": 80,
  "marker": "ferrite-live-1",
  "mem_mib": 256,
  "pidfile": "/tmp/ferrite_vm.pid",
  "web_pidfile": "/tmp/ferrite_web.pid",
  "web_dir": "/tmp/ferrite_monitor",
  "status_title": "Ferrite kiosk monitor"
}
```

`vnc_display: 1` (VNC display **:1** → TCP `127.0.0.1:5901`) and
`web_port: 80` (the standard web port) are the appliance contract.

## Part 2 — the launcher `/app/launch.sh`

It must:

1. Accept an optional first argument: a **config JSON path**. With no argument
   it reads `/app/kiosk.conf`; with an argument it reads that JSON file
   instead. launch.sh must work when given a *different* config file that
   changes `vnc_display`, `web_port`, `marker`, `mem_mib`, `pidfile`,
   `web_pidfile` and `web_dir` — the hidden tests will hand it a variety of
   such configs.
2. After parsing the config, **tear down any previously started VM/web service
   recorded in that config** (kill the pids in `pidfile`/`web_pidfile`, remove
   the pidfiles) so the same config can be restarted (idempotent).
3. Start the emulated machine in the **background** with
   `qemu-system-x86_64`, guest memory `mem_mib` MiB, the guest VGA as a **VNC
   server on VNC display `:<vnc_display>`** (display `1` listens on TCP
   `127.0.0.1:5901`, display `0` on `5900`, display `3` on `5903`, ...; qemu
   flag: `-vnc :<vnc_display>`), and:
   - `-display none` (no local window — there is no X server),
   - `-nic none` (there is no guest networking),
   - **no** `-kernel` (firmware stage; the machine must stay up on its
     firmware alone).
   Write the qemu pid to the config's `pidfile`.
4. Start a tiny **monitoring web server on the config's `web_port`** serving
   the web root from the config's `web_dir`, containing:
   - an `index.html` page that at least contains the config's `status_title`
     string and the config's `marker` string;
   - the endpoint `/cgi-bin/status.json` (see Part 3). (You may use
     `busybox httpd` from the host busybox binary — it serves CGI from a
     `cgi-bin/` directory under the web root — or any small HTTP server
     already installed.)
   Write the web-server pid to `web_pidfile`.
5. **Poll until the kiosk is up**: the qemu pid is alive, the VNC port
   (`5900 + vnc_display`) and the web port are both reachable. Then print
   `KIOSK READY` and exit **0**. If the kiosk does not come up within ~90s,
   exit non-zero.

## Part 3 — the live status endpoint `/app/status.cgi`

`/app/status.cgi` is the program that, when installed as the web plane's
`/cgi-bin/status.json` handler, answers an `HTTP GET` with a valid JSON
object (plus whatever HTTP headers it needs) carrying the **live** kiosk
state:

```json
{
  "marker": "<config marker>",
  "status_title": "<config status_title>",
  "vnc_display": <int>,
  "vnc_port": <int, equal to 5900 + vnc_display>,
  "web_port": <int>,
  "mem_mib": <int>,
  "qemu_pid": <int, the pid from the config's pidfile>,
  "alive": <1 if that pid is still alive else 0>,
  "uptime_sec": <int, seconds since the VM started, else 0>
}
```

- The endpoint must always reflect the **current** state — in particular
  `qemu_pid` must equal the pid actually written to the config's `pidfile`
  and `alive` must be 1 while that process is running. Compute liveness at
  request time (read the pidfile, `kill -0` the pid); do not bake a stale
  answer in.
- Since `status.cgi` is installed per-config by `launch.sh` (it may be
  parameterised by the config at install time or read state written by
  `launch.sh`), it must produce correct output for whatever config was last
  launched — including the hidden ones.

## Verification semantics (what "worked" means)

After `bash /app/launch.sh [config]` returns 0, an independent verifier will:

1. confirm the qemu process recorded in the config's `pidfile` is **still
   alive**, and that its command line really runs the VM with the config's
   display (`-vnc :<vnc_display>`), `-display none`, `-nic none`, and the
   config's memory;
2. confirm via the **listener table** (`netstat`/`ss`) that the VNC port
   (`5900 + vnc_display`) and the web port are being listened on, and
   additionally connect to the VNC port and check it speaks the RFB protocol
   (a real VNC greeting);
3. `HTTP GET` the web port and see the `status_title` and `marker` strings;
4. `HTTP GET /cgi-bin/status.json` and check the live fields: `qemu_pid`
   equal to the pidfile pid and `alive == 1`, `vnc_port == 5900 +
   vnc_display`, and the config's `marker`, `status_title`, `vnc_display`,
   `web_port`, `mem_mib` echoed correctly;
5. re-run `bash /app/launch.sh` with the **same** config and with **hidden**
   configs (different display/port/paths/titles/markers), verifying the
   endpoint and listeners follow the new config each time.

Do not fake any of this with plain file servers pretending a VM exists — the
emulated machine itself must be running.

## Constraints

- Write only under `/app` (plus `/tmp` as scratch). Leave no stray background
  processes other than the one kiosk VM/web server you were asked to keep up.
- No network access is needed; qemu and busybox are already installed.
- The verifier kills the recorded processes between scenarios; launch.sh must
  still work when re-run afterwards (idempotent).
