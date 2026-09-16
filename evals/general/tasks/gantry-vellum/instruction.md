# gantry-vellum — stabilise the enrichd event service

## Situation

`/app/enrichd` is the git checkout of **enrichd**, a streaming
event-enrichment service written in pure Python 3.12 (standard library only,
no third-party packages, no network). Collectors push JSON-lines telemetry
events into it over a pipe; it enriches each event with derived features and
writes one enriched object per event to an output path. In production it is
deployed as a **long-running process** under a supervisor that restarts it on
crash, so its steady-state behaviour under sustained throughput is a first
-class requirement.

The checkout is complete and its unit suite is green:

```
cd /app/enrichd && python3 -m unittest discover -s tests -t . -q
```

Functionally the service behaves correctly: enrichment output matches the
contract below. There is one incident, however. Under sustained load a
long-running instance's **resident memory grows without bound**. It is not a
slowdown and it is not a crash — output stays correct the whole time — but
left running, RSS climbs for hours and the process eventually has to be
restarted for memory, which drops and re-enriches everything behind the
collectors.

## Task

Find the cause of the unbounded memory growth in `/app/enrichd` and fix it.

Acceptance is measured:

1. **Memory must stabilise.** When a workload is fed through the service, the
   process's RSS may rise during warm-up, but the growth between the first
   half and the second half of the run must be negligible (the verifier
   samples the process family RSS from `/proc` while the run is in progress
   and enforces this with a declared bound).
2. **Output must not change.** The emitted enrichment must stay exactly as
   defined by the contract below — same keys, same values, same precision —
   for every event.
3. **The unit suite must keep passing.**

You may modify any file under `/app/enrichd` and add files if you need them
(extra tests are welcome). Do not modify anything outside `/app/enrichd`
(including `/app/tools/` — fixture tooling, you should not need it) and do
not change the service's external interface.

## How the service is driven (interface contract)

```
python3 -m enrichd process --output OUT.jsonl [--input PATH|-] [--flush-every N] [--max-profiles N]
python3 -m enrichd version
```

* `process` reads one event (JSON object) per line from the input stream —
  stdin by default (`-`), or `--input PATH` — and writes one enriched object
  per line to `--output`, in input order.
* The process keeps running as long as the input stream is open. When the
  stream closes it must drain, flush, and **exit 0**. SIGTERM/SIGINT may be
  used to drain early, still exiting 0 after flushing.
* `--flush-every N` controls how often the output sink flushes; `--max-profiles`
  exists and must keep working, but the fix must not depend on a caller
  passing it.

You can reproduce the incident yourself:

```
python3 -m enrichd process --input workloads/visible.jsonl --output /tmp/out.jsonl
```

(`/app/enrichd/workloads/visible.jsonl` is a production-shaped load fixture:
1,120 events from 160 logical clients, whose wire spellings vary in casing,
padding, interior whitespace and a per-round collector tag `~b<n>`.) A simple
RSS sampler over `/proc/<pid>/status` while that runs shows the growth; a
fix that makes a second half-look plateau at the level reached after warm-up
is the target.

## Enrichment contract

An input event has the fields `client` (string), `ts` (integer epoch
seconds), `kind` (string) and optional `amount` (number). The output object
contains every original field **plus exactly these enrichment fields**:

| Field           | Value                                                             |
|-----------------|-------------------------------------------------------------------|
| `client_key`    | canonical spelling of `client`: lowercase, runs of whitespace collapsed to one space, any `~tag` suffix stripped (e.g. `Acct 001~b7` → `acct 001`); this is the identity the service groups by |
| `day`           | UTC calendar date of `ts`, `YYYY-MM-DD`                           |
| `segment`       | behaviour segment, integer 0..5 (derived from the daily behaviour digest) |
| `digest_mean`   | mean of the client's 2048-value daily behaviour digest, float     |
| `digest_energy` | sqrt(mean of squared digest values), float                        |
| `digest_l1`     | mean absolute digest value, float                                 |

Floats are rounded to 6 decimal places. The three digest scalars and the
segment are pure functions of (canonical client, day); every event for the
same canonical client on the same day must carry the same values. Events
that cannot be parsed are skipped and do not produce output.

## How your fix is judged

The verifier feeds four workloads through the service — the visible fixture
and three hidden ones of different shapes (different client counts, round
counts, and day spans) — one batch at a time so the process stays alive while
RSS is sampled from `/proc` between batches. Every workload must:

* exit 0 and emit exactly one line per input event;
* match the enrichment contract exactly (values equal within 1e-6, keys and
  integers exact);
* show RSS growth between the first and second half of the run below the
  declared bound.

The shipped unit suite must additionally still pass. Do not throttle or
stall the pipeline to fake stability — the verifier paces the input itself,
and memory must genuinely stop growing while throughput is maintained.