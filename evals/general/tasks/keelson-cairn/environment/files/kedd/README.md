# kedd — beacon-sighting journal daemon

kedd ingests a **workload** — a batch of beacon-sighting events — through a
fixed-size worker pool and writes one ordered, durable journal line per event.
It is a long-running daemon: it comes up, reports readiness, processes the
batch, and stays alive until the operator signals it to stop.

## Layout

| Path | What it is |
|---|---|
| `src/cairn/` | the daemon sources (package `cairn`) |
| `build/` | clean build output (produced by `build.sh`) |
| `workloads/sample/workload.txt` | a sample workload for experimentation |
| `tests/check.sh` | small semantic check suite, green on a pristine tree |
| `tools/gen_workloads.py` | deterministic workload generator (provenance) |

## Build and run

```
bash build.sh            # javac -> build/
bash run.sh --workload <file> --journal <file> --ready <file> --state <dir>
```

The launcher execs the JVM in the foreground, so the process an operator
signals **is** the daemon. All four flags are required:

| Flag | Meaning |
|---|---|
| `--workload` | event list to ingest (format below) |
| `--journal` | output journal path (created; truncated if present) |
| `--ready` | readiness marker path; the daemon writes `READY\n` once all events are accepted |
| `--state` | state directory for runtime side effects (ticker heartbeat log) |

## Workload format

One event per line: `<ordinal>,<payload>,<width>`. Blank lines and `#`
comments are ignored. Ordinals must run `0..N-1` contiguously; payloads must
match `[A-Za-z0-9._-]+`; widths are integers in `0..2000`, the unit
processing cost of the event. A malformed workload is rejected at startup.

## Journal format

The journal is a durable, strictly-ordered transcript of the processed
events: one line per event, in ascending ordinal order, exactly

```
<ordinal>|<payload>|<digest>
```

where `<digest>` is the first 16 hex characters (lowercase) of the SHA-256,
hex-encoded, of the UTF-8 bytes of `<ordinal>:<payload>:<width>`. Lines are
fsynced before the next line is admitted. After a clean stop the journal
contains exactly one line per workload event — no more, no less, no gaps.

## Lifecycle contract

1. The daemon parses the workload and accepts every event into the pool.
2. It writes the readiness marker — only after every event is accepted.
3. It processes events and journals them until the operator sends **SIGTERM**.
4. On SIGTERM the daemon stops cleanly: it finishes every accepted event,
   stops its housekeeping threads, flushes and closes the journal, and the
   process exits **within a couple of seconds** of the signal. A clean stop
   leaves the journal complete and ordered as described above.

The running daemon must never exit on its own: absent a signal it keeps
accepting and processing, which is what makes step 3 a real daemon lifecycle.