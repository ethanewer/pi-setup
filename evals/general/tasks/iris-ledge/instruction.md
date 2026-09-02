# TASK: iris-ledge — run a tiny emulated guest as a background service, drive it over a monitor console and a serial redirect, compile a static program inside it, and complete a headless render.

You are working inside a single host container. Your job is to author a driver
script `/app/run.sh` (plus a `/app/result.json`) that boots a *tiny* Linux guest
under the QEMU **software** emulator (TCG — there is **no KVM** and no nested
virtualisation), keeps that emulator running in the background as a persistent
service, talks to the guest through a **monitor console** and a **serial
redirect** on loopback ports, compiles and runs a **statically-linked
assembly-level program inside the guest**, and drives an emulated renderer to
the completion of its first frame.

Everything must be done for real inside the emulated guest; then the emulator
must be left **running** (background service) — it must not be torn down.

## What the harness already provides in `/app`

- `/app/vmlinuz` — a Linux kernel for the guest.
- `/app/guest-initrd.cpio.gz` — a tiny root filesystem (busybox + the 9p modules
  needed for a shared volume). It is intentionally *small*: it has no compiler.
  You may **not** modify either file.
- A full C toolchain (`gcc`, `binutils`, glibc headers) is installed in the host
  container. The guest reaches it through the emulated shared volume.
- `qemu-system-x86_64` and friends are installed.
- `python3`, `bash`, `timeout`, `sed`, `grep`, `wc` are available.

### The guest boot contract (read carefully)

The bundled guest `init` does exactly this once booted:

1. mounts `proc`/`sysfs`;
2. loads the 9p kernel modules and attaches the 9p shared volume with mount tag
   **`hostroot`** (supplied by you on the qemu command line) at `/hr`;
3. if a file **`/hr/opt/iris/guest_work.sh`** exists and is executable, it runs
   `chroot /hr /bin/bash /opt/iris/guest_work.sh`, i.e. it enters the host
   container's root filesystem and runs your guest-side driver there;
4. prints a `IRIS_GUEST_IDLE` marker and drops to a busybox `sh` prompt on the
   serial console.

Consequences you must exploit:

- To give the guest a compiler, share the **host container root** into the
  guest: launch qemu with
  `-virtfs local,path=/,mount_tag=hostroot,security_model=none`. Because the
  guest then holds the whole container root via 9p, `chroot`ing into it makes
  `gcc`, the linker/assembler and the C headers available for **in-guest**
  compilation. The guest shares the same x86_64 ABI as the host, so it can run
  the container's toolchain; produce **static** binaries so the compiled guest
  programs need no dynamic loader.
- Write your guest-side driver to **`/opt/iris/guest_work.sh`** *before* you
  start qemu (inside the container, e.g. under the 9p-shared root), along with
  any sources and a scenario file. Have the guest write its outputs (compiled
  program, rendered frame, status file) under **`/opt/iris/work/`**; because
  that directory lives on the shared volume, the host can read them after the
  guest finishes.

## QEMU launch requirements (for `/app/run.sh`)

Boot the tiny guest in the **background** (the emulator must keep running):

- Binary: `qemu-system-x86_64`
- Accelerator: TCG only (`-accel tcg`); do **not** add `-enable-kvm`.
- `-kernel /app/vmlinuz -initrd /app/guest-initrd.cpio.gz`
- `-append "console=ttyS0 panic=-1 rdinit=/init"`
- `-nographic -no-reboot -no-shutdown`
- `-virtfs local,path=/,mount_tag=hostroot,security_model=none`
- QEMU monitor, telnet-served on a loopback port:
  `-monitor telnet:127.0.0.1:<MONITOR_PORT>,server,nowait`
- Serial console redirected to a loopback "telnet" port:
  `-serial tcp:127.0.0.1:<SERIAL_PORT>,server,nowait`
- Redirect qemu's stderr/stdout to a log so it stays detached.

The monitor socket accepts QEMU HMP commands (e.g. `info cpus` works). The
serial redirect yields the guest's busybox shell prompt and accepts keystrokes.

## The driver contract — `/app/run.sh`

`/app/run.sh` must be a self-contained, executable bash script with signature:

```
/app/run.sh [SCENARIO_JSON] [OUTDIR]
```

- `SCENARIO_JSON` defaults to `/app/scenario-main.json`.
- `OUTDIR` defaults to `/app`.
- It must generalize: the harness will call it again on **hidden** scenarios
  (different exit status / frame size / seed / ports / frame name), so it may
  not hard-code a single case.

For *any* scenario it must:

1. Kill any previously running qemu instance so it can bind fresh ports.
2. Read the scenario JSON (width, height, seed, exit_status, monitor_port,
   serial_port, frame) and prepare the shared work area:
   - write `/opt/iris/scenario.json` (the exact scenario used),
   - write an executable `/opt/iris/guest_work.sh` that does the in-guest work
     below,
   - clear `/opt/iris/work`.
3. Boot the guest per the launch requirements above with the scenario's
   **monitor_port** and **serial_port**, in the background.
4. Wait until the guest has finished its work (poll the shared volume for the
   result file written by the guest).
5. Copy the rendered frame into `OUTDIR/<frame>`.
6. Write `OUTDIR/result.json` (schema below) and **leave qemu running** in the
   background.

### In-guest work (`/opt/iris/guest_work.sh`, executed by the guest via chroot)

- **Compile & run a static assembly-level program.** Create a C source that
  contains inline assembly which sets the program's exit status to exactly
  `exit_status`, e.g.
  `int main(void){ int x; asm("movl $N,%0" : "=r"(x)); return x; }`
  with `N = exit_status`. Compile it **statically** (`gcc -static ...`), run it
  inside the guest, and capture its exit status.
- **Drive a renderer to completion.** Create a renderer that, for the given
  `width` × `height` and `seed`, runs a full frame-fill render loop and writes a
  binary **P6 PPM** image: header `P6\n<width> <height>\n255\n` followed by
  exactly `3*width*height` bytes (3 RGB bytes per pixel). The pixel values must
  be derived from the seed (using a deterministic generator so different seeds
  give different frames) and must not be all identical. Compile it statically
  and run it inside the guest.
- Write the result back to the shared volume under `/opt/iris/work/`:
  - the guest exit status of the compiled program (e.g. `prog.exit`),
  - the rendered frame (e.g. `frame.ppm`),
  - a small status/done marker so the host knows the work finished.

You are expected to implement these steps *inside the emulated guest* (through
the shared 9p volume + chroot), not by running gcc on the host for the guest.

## Scenario JSON schema

```json
{
  "name": "main",
  "exit_status": 42,
  "width": 64,
  "height": 48,
  "seed": 7,
  "monitor_port": 55321,
  "serial_port": 55322,
  "frame": "frame.pgm"
}
```

Limits the hidden cases stay inside: `width,height` in `[16,512]`,
`exit_status` in `[1,255]`, ports are distinct loopback ports, `frame` is a
short basename.

## `/app/result.json` schema (exactly these keys)

```json
{
  "task": "iris-ledge",
  "scenario": "<name>",
  "exit_status": 42,
  "program_exit": 42,
  "program_exit_ok": true,
  "compiled_static": true,
  "render_ok": true,
  "frame": "frame.pgm",
  "frame_width": 64,
  "frame_height": 48,
  "frame_seed": 7,
  "frame_bytes": 9216,
  "monitor_port": 55321,
  "serial_port": 55322,
  "monitor_ok": true,
  "serial_ok": true,
  "qemu_pid": 1234,
  "qemu_alive": true,
  "background": true
}
```

- `program_exit` must equal `exit_status` (then `program_exit_ok` is true).
- `frame_bytes` is the size in bytes of the PPM written to `OUTDIR/<frame>`
  (must equal `3*width*height` for a well-formed P6 image).
- `render_ok` is true only when the frame was produced with the right size.
- `monitor_ok` / `serial_ok` are true when you verified the sockets actually
  respond (the verifier also re-checks these itself).
- `qemu_pid` / `qemu_alive` / `background` describe the background emulator you
  left running.

## What the verifier will do (do not rely on it, but satisfy it)

It re-executes `/app/run.sh` on the main scenario and on hidden scenarios, then
for each: parses `OUTDIR/result.json`; checks `program_exit == exit_status`,
`render_ok`, and that `OUTDIR/<frame>` is a correct `width`×`height` P6 PPM with
the right byte count and non-uniform pixels; independently connects to
`monitor_port` (sends an HMP command, expects `(qemu)`-style HMP output) and to
`serial_port` (sends a command, expects the echo), proving the emulator is still
alive as a background service. Note that as long as the **last** scenario's qemu
is running, its monitor/serial sockets are what the verifier probes.

## Constraints & scoring

- Do not modify `/app/vmlinuz` or `/app/guest-initrd.cpio.gz`.
- Do not shut qemu down at the end — the persistent background service is part
  of the task.
- `/app/run.sh` must work when invoked with no arguments (using
  `/app/scenario-main.json` → `/app/result.json`) and with explicit
  scenario/outdir arguments.
- Produce `/app/result.json` as one of the deliverables (run `run.sh` with the
  main scenario to create it).
