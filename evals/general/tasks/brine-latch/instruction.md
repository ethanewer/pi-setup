# ColdBrine relay: reclaim a rotated-away snapshot from the live process

The ColdBrine telemetry relay on this appliance rotates its snapshot file at
startup: it **opens the snapshot, then deletes (unlinks) the pathname while
keeping the file descriptor open**, and keeps running. The bytes of the
snapshot therefore survive only inside that open descriptor of the running
relay process — the file no longer exists under any name.

You must write a **reusable** recovery program `/app/reclaim.py` that reclaims
the content of the unlinked-but-still-open file, and leave the recovered
snapshot at `/app/recovered.bin`. The grader re-runs your program against
**fresh hidden relay processes** holding different payloads, so the recovery
logic must be fully general — never assume the payload, the pid, or the
descriptor number.

## Environment

- Working directory: `/app`.
- The relay daemon is already running. It writes its **PID** (ASCII digits) to
  the pidfile **`/tmp/brine-vault/relay.pid`**.
- The relay also keeps other, still-linked files open (e.g. a live calibration
  table under `/app/vault/`) — **do not confuse those with the rotated
  snapshot**. Exactly one of the relay's open descriptors refers to a file
  whose directory entry has been removed.
- Python 3.12 is available as `python3`; standard library only; no network.

## Deliverables (both required)

1. `/app/reclaim.py` — a runnable Python program with this interface:

   ```
   python3 /app/reclaim.py [PIDFILE] [OUTFILE]
   ```

   - No arguments → `PIDFILE = /tmp/brine-vault/relay.pid`,
     `OUTFILE = /app/recovered.bin`.
   - Two arguments → read the pid from `<PIDFILE>` and write the recovered
     bytes to `<OUTFILE>`.
   - The program must exit with status 0 on success.

   Recovery procedure: read the PID from the pidfile, inspect the process's
   open descriptors (on Linux, the symlinks under `/proc/<pid>/fd/`), find the
   one whose target marks a **deleted** file (the symlink target ends with
   `(deleted)`), and copy that descriptor's content **byte-for-byte** to the
   output path. Reading via `/proc/<pid>/fd/<n>` or duplicating the descriptor
   are both acceptable; what matters is the exact original bytes.

2. `/app/recovered.bin` — the bytes your program recovers **on the visible
   appliance** (the running relay's rotated snapshot), produced by running:

   ```
   python3 /app/reclaim.py
   ```

## Failure modes the grader checks

- Grabbing the **wrong descriptor** (e.g. the still-linked calibration table,
  the pidfile, or the relay's log) instead of the deleted one.
- Writing a stale or partial copy: the recovered output must be **byte-for-byte
  identical** to the payload the relay opened.
- Hard-coding the visible pid, a fixed descriptor number, or the visible
  payload — the program must locate the deleted fd dynamically for any relay
  process.

## Constraints

- Do **not** signal, kill, restart, or otherwise disturb the relay process.
- Do **not** modify anything under `/app/vault/` (the relay already unlinked
  its snapshot; leave the rest as-is).
- Standard library only; no network at build, run, or verify time.
- Exit cleanly (status 0) in both the 0-argument and 2-argument forms.
