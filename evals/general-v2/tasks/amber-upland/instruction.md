# amber-upland — boot a minimal initramfs guest and keep it on display

You are provisioning a tiny emulated VM inside this container **without a GPU, X
server, KVM, systemd, or any networking**, and keeping it running in the
background so a human can watch it.

Work only under `/app`. Create exactly three deliverables:

- `/app/initramfs.gz` — a bootable initrd you build yourself
- `/app/boot.sh`     — the launcher program that boots the guest and keeps
                       the VM running in the background (executable)
- `/app/vnc.conf`    — the runtime config the launcher reads by default

## Part 1 — build the initramfs from the descriptor manifest

Read `/app/files/initramfs_manifest.json`. It is a JSON descriptor listing the
busybox source binary, the shell path, an init banner, and (important) the set of
device nodes and the init behaviour every bootable image must provide.

Produce `/app/initramfs.gz` as a **gzip-compressed newc (cpio) archive** whose
contents satisfy the manifest:

- the static `busybox` binary from the manifest's `busybox_source` is copied to
  `/bin/busybox` inside the archive, and every path in `applet_links` is a
  symlink pointing to `busybox` (so `/bin/sh → busybox`, `/bin/ls → busybox`, ...);
- every `device_nodes` entry exists as a real special file with the exact
  `type` (c) and `major`/`minor` numbers given in the manifest;
- the `/init` program at the archive root is an **executable POSIX shell script**
  that runs each command in `init.mount_steps`, prints the `init.banner` string,
  and finally `exec`s the shell named by `init.exec_shell` (the busybox `sh`);
- the directories listed in `directory_roots` are present.

The point of this step is that your `/app/initramfs.gz` is *derived from* the
manifest — do not hard-code your own unrelated set of device nodes or init.

You may write any helper scripts (e.g. a `build_initrd.sh` or Python builder)
you want under `/app` to construct the archive. Deleting them is fine; only the
three deliverables above will be checked.

## Part 2 — boot the guest, keep it alive, expose VNC + a web monitor

`/app/boot.sh` is the launcher. It must:

1. Accept an optional first argument: a **config JSON path**. With no argument
   it reads `/app/vnc.conf`; with an argument it reads that JSON file instead.
2. After parsing the config, **tear down any previously started VM/web service
   recorded in that config** (kill by pidfile, remove the console socket) so the
   same config can be restarted (idempotent).
3. Boot the guest in the **background** using the kernel `/boot/vmlinuz` and
   initrd `/app/initramfs.gz`, in software emulation (TCG), with:
   - guest memory 256 MiB;
   - `console=ttyS0` so the shell is reachable over a serial device;
   - `rdinit=/init` so our init script is run;
     - the serial console exposed as a **UNIX domain socket server** at the
       config's `console_socket` (qemu flag: `-serial
       unix:<path>,server=on,wait=off`);
   - **and** the guest VGA as a VNC server on VNC display `:<vnc_display>`
     (e.g. display `0` listens on TCP `127.0.0.1:5900`, display `3` on `5903`).
   - use `-nic none` and `-display none` — there is no guest networking.
4. Start a tiny **monitoring web server** on the config's `web_port` serving an
   `index.html` page that at least contains the config's `status_title` string.
   (You may use `busybox httpd` from the host busybox binary, or any small HTTP
   server already installed.)
5. Write the qemu process id (and web-server pid) to the config's `pidfile` /
   `web_pidfile`, then **poll until the VM is up**: the qemu pid is alive, the
   VNC port (`5900 + vnc_display`), the web port, and the console socket are
   all reachable. Then print `VM READY` and exit **0**. If the guest fails to
   boot within ~90s, exit non-zero.

The config JSON you must support (the fields boot.sh consumes) is exactly:

```json
{
  "vnc_display": 0,
  "web_port": 80,
  "marker": "amber-shell-0",
  "console_socket": "/tmp/amber_console.sock",
  "pidfile": "/tmp/amber_vm.pid",
  "web_pidfile": "/tmp/amber_web.pid",
  "web_dir": "/tmp/amber_monitor",
  "status_title": "amber-upland VM monitor",
  "kernel": "/boot/vmlinuz",
  "initrd": "/app/initramfs.gz"
}
```

`/app/vnc.conf` is the **default config** and must contain exactly the fields
above with `vnc_display: 0`. boot.sh must also work when given a *different*
config file that changes `vnc_display`, `web_port`, `marker`, `status_title`,
`console_socket`, `pidfile` and `web_pidfile` — the hidden tests will hand it a
variety of such configs.

## Verification semantics (what "worked" means)

After `bash /app/boot.sh [config]` returns 0, an independent verifier will:

1. unzip your `/app/initramfs.gz` and confirm it is a newc cpio archive holding
   `/bin/busybox`, the manifest device nodes (correct type/major/minor), and an
   executable `/init` whose body prints the banner and `exec`s `/bin/sh`;
2. confirm the qemu process recorded in the config's pidfile is **still alive**
   (the VM was left running in the background, not foregrounded/blocked);
3. connect to the VNC port for that display and see a TCP listener;
4. **connect to the config's `console_socket`**, send the literal command
   `echo <marker>` (the config's own marker string), and read back the echoed
   marker text — proving a real interactive `/bin/sh` is running in the guest;
5. `HTTP GET` the config's `web_port` and see the `status_title` string.

Do not try to run qemu as root-only services, bind reserved kinds the guest can't
do, or fake any of this with netcat echo servers — the guest itself must boot and
reach a shell.

Write only under `/app` (plus `/tmp` as scratch). Leave no stray background
processes other than the one running VM/web server you were asked to keep up.