# Ferrite wall-kiosk appliance

You are provisioning the **Ferrite** wall-mounted kiosk: a tiny emulated VM
that runs inside this container **without a GPU, X server, KVM, systemd, or
any networking**, is kept running in the background, and is remotely
observable through **VNC on display :1** and a **monitoring web page on the
standard web port (80)**.

Work only under `/app` (plus `/tmp` as scratch). Create exactly three
deliverables:

- `/app/kiosk.gz`   — the bootable initrd you build yourself
- `/app/launch.sh`  — the launcher that boots the kiosk and keeps it running
                      (executable)
- `/app/kiosk.conf` — the runtime config the launcher reads by default

## Part 1 — build the initrd from the kiosk descriptor

Read `/app/files/kiosk_manifest.json`. It is a JSON descriptor listing the
static busybox binary, the applet symlinks, the exact device nodes, the
directory roots, and the init behaviour every bootable kiosk image must
provide.

Produce `/app/kiosk.gz` as a **gzip-compressed newc (cpio) archive** whose
contents satisfy the descriptor:

- the static `busybox` binary from the descriptor's `busybox_source` is copied
  to `busybox_dest` inside the archive, and every path in `applet_links` is a
  symlink pointing to `busybox` (so `/bin/sh → busybox`, `/bin/echo →
  busybox`, ...);
- every `device_nodes` entry exists as a real **character special file** with
  the exact `major`/`minor` numbers given in the descriptor (the kiosk
  framebuffer node `/dev/fb0` at 29:0 is part of the appliance contract);
- the directories listed in `directory_roots` are present;
- the `/init` program at the archive root is an **executable POSIX shell
  script** that runs each command in `init.mount_steps`, prints the
  `init.banner` string, and finally `exec`s the shell named by
  `init.exec_shell` (the busybox `sh`).

The point of this step is that `/app/kiosk.gz` is *derived from* the
descriptor — do not hard-code an unrelated device set or init.

You may keep any helper scripts you used under `/app`; only the three
deliverables above are checked.

## Part 2 — boot the kiosk, keep it alive, expose VNC :1 + the web monitor

`/app/launch.sh` is the launcher. It must:

1. Accept an optional first argument: a **config JSON path**. With no argument
   it reads `/app/kiosk.conf`; with an argument it reads that JSON file
   instead.
2. After parsing the config, **tear down any previously started VM/web service
   recorded in that config** (kill by pidfile, remove the console socket) so
   the same config can be restarted (idempotent).
3. Boot the guest in the **background** using the kernel `/boot/vmlinuz` and
   initrd `/app/kiosk.gz`, in software emulation (TCG), with:
   - guest memory 256 MiB;
   - `console=ttyS0` and `rdinit=/init` so our init runs and the shell is
     reachable over a serial device;
   - the serial console exposed as a **UNIX domain socket server** at the
     config's `console_socket` (qemu flag: `-serial
     unix:<path>,server=on,wait=off`);
   - the guest VGA as a **VNC server on VNC display `:1`** for the default
     config — i.e. `vnc_display` from the config: display `1` listens on TCP
     `127.0.0.1:5901`, display `0` on `5900`, display `3` on `5903`, and so on
     (qemu flag: `-vnc :<vnc_display>`);
   - use `-nic none` and `-display none` — there is no guest networking.
4. Start a tiny **monitoring web server on the config's `web_port`** (port
   **80** for the default config) serving an `index.html` page that at least
   contains the config's `status_title` string. (You may use `busybox httpd`
   from the host busybox binary, or any small HTTP server already installed.)
5. Write the qemu process id (and web-server pid) to the config's `pidfile` /
   `web_pidfile`, then **poll until the kiosk is up**: the qemu pid is alive,
   the VNC port (`5900 + vnc_display`), the web port, and the console socket
   are all reachable. Then print `KIOSK READY` and exit **0**. If the guest
   fails to come up within ~90s, exit non-zero.

The config JSON you must support (the fields launch.sh consumes) is exactly:

```json
{
  "vnc_display": 1,
  "web_port": 80,
  "marker": "ferrite-live-1",
  "console_socket": "/tmp/ferrite_console.sock",
  "pidfile": "/tmp/ferrite_vm.pid",
  "web_pidfile": "/tmp/ferrite_web.pid",
  "web_dir": "/tmp/ferrite_monitor",
  "status_title": "Ferrite kiosk monitor",
  "kernel": "/boot/vmlinuz",
  "initrd": "/app/kiosk.gz"
}
```

`/app/kiosk.conf` is the **default config** and must contain exactly the
fields above with `vnc_display: 1` and `web_port: 80`. launch.sh must also
work when given a *different* config file that changes `vnc_display`,
`web_port`, `marker`, `status_title`, `console_socket`, `pidfile` and
`web_pidfile` — the hidden tests will hand it a variety of such configs.

## Verification semantics (what "worked" means)

After `bash /app/launch.sh [config]` returns 0, an independent verifier will:

1. unpack `/app/kiosk.gz` and confirm it is a newc cpio archive holding
   `/bin/busybox`, the descriptor device nodes (correct type/major/minor),
   the directory roots, and an executable `/init` whose body runs the mount
   steps, prints the banner, and `exec`s `/bin/sh`;
2. confirm the qemu process recorded in the config's pidfile is **still
   alive** (the kiosk was left running in the background);
3. confirm via the **listener table** (`netstat`/`ss`) that the VNC port
   (`5900 + vnc_display`) and the web port are being listened on, and
   additionally connect to both;
4. `HTTP GET` the config's `web_port` and see the `status_title` string;
5. **connect to the config's `console_socket`**, send the literal command
   `echo <marker>` (the config's own marker string), and read back the echoed
   marker text — proving a real interactive `/bin/sh` is running in the guest.

Do not fake any of this with plain echo servers — the guest itself must boot
and reach a shell.

## Constraints

- Write only under `/app` (plus `/tmp` as scratch). Leave no stray background
  processes other than the one kiosk VM/web server you were asked to keep up.
- No network access is available or needed; everything (qemu, busybox, the
  host kernel image) is already installed in the container.
- Do not modify `/app/files/kiosk_manifest.json`.
