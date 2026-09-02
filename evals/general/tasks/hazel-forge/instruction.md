# hazel-forge — capped job runner for the Larkspur render farm

The Larkspur render farm dispatches batches of short render jobs from a single
asyncio event loop. Workers are expensive, so **at most `limit` jobs may be
executing at any instant**, results must come back in submission order, and a
failing job must abort the batch without letting queued jobs sneak onto the
farm. You will write one module, `/app/rungate.py`, plus a self-test artifact.

The grader imports `/app/rungate.py` and re-runs it against **hidden job
batches** (different limits, batch sizes, durations, and a hidden failure
case), so nothing may be tuned to a single visible example.

## Deliverables

1. `/app/rungate.py` — an importable asyncio module (stdlib only; no third
   party packages).
2. `/app/selftest.json` — produced by running
   `python3 /app/rungate.py --selftest /app/selftest.json` (exact command;
   see the CLI contract below).

## Module contract

`/app/rungate.py` must expose exactly this public API (top-level, importable):

```python
class RunGate:
    def __init__(self, limit: int): ...
    async def run_jobs(self, factories: list) -> list: ...

async def gather_capped(factories: list, limit: int) -> list: ...
```

Semantics (all are probed by hidden cases):

- **`RunGate(limit)`** raises `ValueError` if `limit < 1` (including `0` and
  negatives).
- **`run_jobs(factories)`**: `factories` is a list of zero-argument callables,
  each returning an awaitable (a coroutine) when called. Jobs must be wrapped
  and launched **inside** the concurrency gate: at most `limit` of the jobs are
  executing at any instant. It is invalid to pre-create `asyncio.Task` objects
  for all jobs before any gate slot is free (that launches everything at once).
- The returned list holds the job results **in the same order as the input**,
  regardless of completion order. Each factory must be called **at most once**
  and only for jobs that actually run.
- An **empty** `factories` list returns `[]` (and creates no tasks).
- **Failure propagation**: if a job raises an exception, `run_jobs` must
  propagate that exception to its caller. Jobs that had **not started** when
  the failure surfaced must never run (their factories must never be called).
- **Cancellation**: if the task running the whole batch is cancelled, the call
  raises `asyncio.CancelledError` and pending (never-started) jobs must never
  run.
- **`gather_capped(factories, limit)`** is a thin convenience:
  `return await RunGate(limit).run_jobs(factories)`.

Implementation hints (not mandatory): an `asyncio.Semaphore(limit)` around a
`create_task` per job, or a sliding worker pool. What matters is the observable
behavior above.

## CLI contract

`python3 /app/rungate.py --selftest <out.json>` runs a deterministic built-in
self-test and writes a JSON report, then exits 0:

- 10 jobs, job `i` sleeping `(0.01 + 0.01 * (i % 3))` seconds and returning
  `i * i`, run through the gate with `limit = 4`.
- The report JSON must have exactly these keys:
  ```json
  {"limit": 4, "jobs": 10, "results": [0, 1, 4, ...],
   "peak_concurrency": <int>, "ok": true}
  ```
- `results` must be `[0, 1, 4, 9, ..., 81]` in order.
- `peak_concurrency` must be `>= 1` and `<= 4` — measure the true instantaneous
  overlap inside your own gate (e.g. increment a counter when a job starts and
  decrement when it finishes, tracking the maximum).

Exit non-zero only if the self-test itself fails its own invariants.

## Hidden cases the grader runs

The grader builds its own factories (async jobs that track the number of
currently-running jobs and sleep for fixed durations) and checks:

1. **Over-subscribed batch**: limit `3`, 9 jobs of mixed durations (10–40 ms)
   → peak concurrency `<= 3`, all 9 results present, in input order.
2. **Serial gate**: limit `1`, 6 jobs → jobs strictly never overlap
   (peak `<= 1`), results in order.
3. **Failure**: limit `2`, 6 jobs where job index `2` raises
   `ValueError("boom")` immediately → awaiting `run_jobs` raises a
   `ValueError`; the never-started jobs' factories were never called.
4. **Cancellation**: limit `3`, 20 jobs each sleeping 1 s; the batch task is
   cancelled ~100 ms in → `asyncio.CancelledError` propagates and **at most 3**
   factories were ever called.
5. **Bad construction**: `RunGate(0)` and `RunGate(-2)` raise `ValueError`;
   `run_jobs([])` returns `[]`.
6. Your `/app/selftest.json` matches the contract above.

## Constraints

- Python 3.12, asyncio stdlib only; no network access at any point.
- Do not read or import anything under `/tests` or `/solution`.
- Keep everything deterministic in outcome (ordering/results), even though
  wall-clock scheduling is naturally asynchronous.
