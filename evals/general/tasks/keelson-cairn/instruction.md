# keelson-cairn: make the kedd journal daemon stop cleanly

You are handed a Java daemon, **kedd**, that ingests a batch of beacon-sighting
events and writes one durable journal line per event. The daemon's steady-state
behavior works: it comes up, reports readiness, processes the workload, and
keeps a complete ordered journal. But it has one serious defect: **when the
operator sends it SIGTERM it does not stop**. The process lingers indefinitely
instead of exiting within the required bound with its journal flushed.

Your job: diagnose why the daemon does not terminate, repair the sources so it
does, and prove the repair. This is a debugging task — the defect is in the
code, not in how the daemon is launched or driven.

## Environment

| Path | What it is |
|---|---|
| `/app/kedd/` | the daemon project (a git repository with history; `git log` works) |
| `/app/kedd/README.md` | the project and operation contract — read it |
| `/app/kedd/src/cairn/` | the sources (package `cairn`) you may edit |
| `/app/kedd/build.sh` | **deliverable** — clean rebuild of `src/` into `build/` |
| `/app/kedd/run.sh` | **deliverable** — launcher: `exec java -cp build cairn.Keddaemon "$@"` |
| `/app/kedd/workloads/sample/workload.txt` | a sample workload for experimentation (do not modify) |
| `/app/kedd/tests/check.sh` | the shipped semantic check suite (must keep passing) |
| `/app/kedd/tools/gen_workloads.py` | deterministic workload generator (provenance) |

Installed: OpenJDK 21 (`javac`/`java`), git, python3, standard shell tools.
No network. Everything needed is on disk.

## The daemon contract (do not change)

Launch shape (all four flags required):

```
bash /app/kedd/run.sh --workload <file> --journal <file> --ready <file> --state <dir>
```

- `--workload` — the event list (`<ordinal>,<payload>,<width>` per line; `#`
  comments and blank lines ignored; ordinals must run 0..N-1 contiguously;
  payloads match `[A-Za-z0-9._-]+`; widths are ints in 0..2000).
- `--journal` — output journal path, created/truncated by the daemon.
- `--ready` — the daemon writes `READY\n` here **only after every event has
  been accepted** by its worker pool.
- `--state` — a state directory the daemon creates for its runtime side files.

Lifecycle: the daemon accepts every event, writes `READY`, processes the batch
concurrently, and then just runs — a daemon does not exit on its own. When the
process receives **SIGTERM** it must stop gracefully: finish every event it
accepted, stop its housekeeping, and exit **well within 60 seconds** of the
signal. A correct repair exits in about ten. The `run.sh` launcher execs the
JVM in the foreground — the process the operator signals is the daemon, and it
must still be the daemon when the verifier signals it (keep this shape).

## The journal contract (unchanged)

Exactly one line per workload event, on disk, in strictly ascending ordinal
order:

```
<ordinal>|<payload>|<digest>
```

where `<digest>` is the first **16 hex characters (lowercase)** of the SHA-256
(hex-encoded) of the UTF-8 bytes of `<ordinal>:<payload>:<width>`. A clean
stop leaves the journal **complete**: every one of the N accepted events
present, no gaps, no extras, no reordering, and the file flushed to disk
before the process exits. You can recompute the expected journal for any
workload with:

```python
import hashlib
hashlib.sha256(("%d:%s:%d" % (ordinal, payload, width)).encode()).hexdigest()[:16]
```

The daemon must also **reject** a malformed workload (non-contiguous ordinals,
bad payload charset, out-of-range width) instead of processing it.

## What to do

Find out why the daemon does not terminate on SIGTERM, and fix it. Some
guidance:

- Reproduce first: launch against the sample workload, wait for `READY`, give
  the batch a moment, then `kill -TERM <pid>` and observe. Then read the
  code around termination carefully.
- Keep the sentence above true: *every accepted event* must be journaled
  before the process may exit, and the journal must stay strictly ordered.
  Weakening the workload, deleting journaling, or exiting early without the
  full transcript all fail the case.
- Validate as you go: `bash /app/kedd/tests/check.sh` stays green, and the
  full contract holds under repeated launches (several times, on the sample
  at least).

## Deliverables

- `/app/kedd/build.sh` — must build the current `/app/kedd/src` into
  `/app/kedd/build` and exit 0. The verifier runs it itself before testing,
  so your source fixes are what gets exercised (edit sources, not jars).
- `/app/kedd/run.sh` — must launch the daemon per the contract above.

There is no report file to write. The deliverable is the repaired daemon
itself.

## Verification (what the grader will do)

For the sample workload and for three hidden workloads (different event
counts, width profiles, and payloads), the grader:

1. runs `bash /app/kedd/build.sh` and `bash /app/kedd/tests/check.sh`;
2. launches the daemon on the workload, waits up to 60s for `READY`;
3. confirms the process is still alive roughly a second after readiness,
   rather than having exited on its own before it was signaled;
4. sends SIGTERM and requires the process to exit within **60 seconds**;
5. recomputes the expected journal from the workload alone and requires the
   journal on disk to match it **line for line** (same count, same ordinals
   in order, same payloads, same digests).

A daemon that hangs on SIGTERM, stops without draining every accepted event,
reorders or drops entries, or exits before it is signaled fails. Fix the
daemon — do not touch the workload fixtures, the check suite, or the git
history, and do not weaken any check to make it pass.