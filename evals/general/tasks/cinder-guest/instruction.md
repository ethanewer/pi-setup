# TASK: cinder-guest — boot a tiny QEMU guest with a live monitor console and a
# serial redirect, then drive the guest's serial shell over the network to do
# real in-guest work, leaving the emulator running as a background service.

You are working inside a single host container. Your job is to author a driver
script `/app/run.sh` (plus a `/app/result.json`) that boots a *tiny* Linux
guest under the QEMU **software** emulator (TCG — there is **no KVM**), keeps
that emulator running in the background, attaches the guest's **QEMU monitor**
as a loopback console, redirects the **guest serial console to a loopback TCP
port**, and then drives the guest's shell *over that serial port* to perform
work inside the emulated machine.

Everything the guest produces must genuinely be produced inside the guest by
commands typed over the serial connection; the emulator must be left **running**
(background service) — it must not be torn down.

## What the harness already provides in `/app`

- `/app/vmlinuz` — a Linux kernel for the guest.
- `/app/guest-initrd.cpio.gz` — a tiny busybox root filesystem. You may **not**
  modify either file.
- `qemu-system-x86_64` is installed. `python3`, `bash`, `pgrep`, `pkill` are
  available.

### The guest boot contract (read carefully)

The bundled guest `init` does exactly this once booted:

1. mounts `proc`/`sysfs`;
2. prints `CINDER_GUEST_BOOT_OK` on the serial console;
3. sets the shell prompt to exactly `CG> ` and prints `CINDER_GUEST_READY`;
4. drops to a busybox `sh` prompt (`CG> `) on the serial console.

Consequences:

- The serial console is the guest's only interface. You talk to it over the
  TCP port you redirect it to, exactly like driving a headless appliance.
- The guest has no persistent storage; to leave artifacts you must mount a
  tmpfs (e.g. on `/ramwork`) from inside the guest over the serial connection.

## QEMU launch requirements (for `/app/run.sh`)

Boot the tiny guest in the **background** (the emulator must keep running):

- Binary: `qemu-system-x86_64`
- Accelerator: TCG only (`-accel tcg`); do **not** add `-enable-kvm`.
- `-kernel /app/vmlinuz -initrd /app/guest-initrd.cpio.gz`
- `-append "console=ttyS0 panic=-1 rdinit=/init"`
- `-m 256M -nographic -no-reboot -no-shutdown`
- QEMU monitor, telnet-served on a loopback port:
  `-monitor telnet:127.0.0.1:<MONITOR_PORT>,server,nowait`
- Serial console redirected to a loopback TCP port:
  `-serial tcp:127.0.0.1:<SERIAL_PORT>,server,nowait`
- Redirect qemu's stderr/stdout to a log so it stays detached.

The monitor socket accepts QEMU HMP commands (`info status` must answer
`VM status: running`). The serial port yields the guest's `CG> ` shell prompt
and accepts keystrokes.

## The driver contract — `/app/run.sh`

`/app/run.sh` must be a self-contained, executable bash script with signature:

```
/app/run.sh [SCENARIO_JSON] [OUTDIR]
```

- `SCENARIO_JSON` defaults to `/app/scenario-main.json`.
- `OUTDIR` defaults to `/app`.
- It must generalize: the harness will call it again on **hidden** scenarios
  (different operands / operation / token / ports), so it may not hard-code a
  single case.

For *any* scenario it must:

1. Kill any previously running qemu instance so it can bind fresh ports.
2. Read the scenario JSON (`name`, `a`, `b`, `op`, `token`, `monitor_port`,
   `serial_port`).
3. Boot the guest per the launch requirements above with the scenario's
   `monitor_port` and `serial_port`, in the background.
4. **Drive the guest over the serial port.** Connect to
   `127.0.0.1:<serial_port>`, wait for the `CINDER_GUEST_READY` marker /
   `CG> ` prompt, then send shell commands that make the *guest*:
   - create `/ramwork` and mount a tmpfs on it;
   - compute `a op b` in-guest with shell arithmetic, where `op` is one of
     `add` (`a + b`), `sub` (`a - b`), `mul` (`a * b`);
   - write the line `<token>|<result>` to `/ramwork/answer.txt`;
   - `cat` that file back so the host can read the line off the serial port.
5. **Verify the monitor.** Connect to `127.0.0.1:<monitor_port>`, wait for the
   `(qemu)` HMP prompt, send `info status`, and confirm the answer reports the
   VM running. Save the monitor exchange to `OUTDIR/monitor.txt`.
6. Save the serial transcript to `OUTDIR/serial.txt`.
7. Write `OUTDIR/result.json` (schema below) and **leave qemu running** in the
   background.

## Scenario JSON schema

```json
{
  "name": "main",
  "a": 12,
  "b": 9,
  "op": "mul",
  "token": "cg-tide-0417",
  "monitor_port": 56321,
  "serial_port": 56322
}
```

Limits the hidden cases stay inside: `a`, `b` in `[1,99]` with `a >= b` when
`op` is `sub`; `op` is `add`, `sub` or `mul`; `token` is a short alphanumeric
token; the two ports are distinct loopback ports.

## `/app/result.json` schema (exactly these keys)

```json
{
  "task": "cinder-guest",
  "scenario": "main",
  "a": 12,
  "b": 9,
  "op": "mul",
  "token": "cg-tide-0417",
  "expected": 108,
  "guest_answer": 108,
  "answer_ok": true,
  "serial_ok": true,
  "monitor_ok": true,
  "monitor_port": 56321,
  "serial_port": 56322,
  "qemu_pid": 1234,
  "qemu_alive": true,
  "background": true
}
```

- `expected` is the host-side value of `a op b`.
- `guest_answer` is the value read back from the guest's `answer.txt` over the
  serial port; `answer_ok` is true only when it equals `expected`.
- `serial_ok` is true when the guest's ready marker, its `CG> ` prompt, and the
  `<token>|<result>` answer line were all observed over the serial connection.
- `monitor_ok` is true when the monitor answered `info status` with the VM
  running.
- `qemu_pid` / `qemu_alive` / `background` describe the background emulator you
  left running.

## What the verifier will do (do not rely on it, but satisfy it)

It re-executes `/app/run.sh` on the main scenario and on hidden scenarios, then
for each: parses `OUTDIR/result.json`; checks `answer_ok`, `serial_ok`,
`monitor_ok`, `qemu_alive` and `background`, and that `guest_answer` equals the
reference value of `a op b`; reads `OUTDIR/serial.txt` and confirms it contains
the `<token>|<result>` line; and then **independently** connects to
`monitor_port` (sends an HMP command, expects `(qemu)`-style output) and to
`serial_port` (sends a fresh shell command, expects its output), proving the
emulator is still alive as a background service with a live, drivable serial
shell.

## Constraints & scoring

- Do not modify `/app/vmlinuz` or `/app/guest-initrd.cpio.gz`.
- Do not shut qemu down at the end — the persistent background service is part
  of the task.
- `/app/run.sh` must work when invoked with no arguments (using
  `/app/scenario-main.json` -> `/app/result.json`) and with explicit
  scenario/outdir arguments.
- Produce `/app/result.json` as one of the deliverables (run `run.sh` with the
  main scenario to create it).