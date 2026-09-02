# Fix the async Dispatcher and prove the cleanup guarantees

## Context

`/app/dispatcher.py` defines `Dispatcher`, which runs a batch of coroutine
"jobs" under a concurrency cap using `asyncio.Semaphore`. Every job is required
to hold exactly one lease from a `LeasePool` while it runs, and to give that
lease back when it finishes **no matter how it finishes** — normally, by raising,
or by being cancelled.

The supplied `dispatch()` implementation is **broken**:

- It spawns every job with `asyncio.create_task(coro)` directly, **bypassing the
  concurrency semaphore and the lease manager** — so it runs far more than
  `max_concurrency` jobs at once.
- On failure or cancellation of the dispatch task, it does **not** cancel the
  still-running jobs and **does not wait** for their cleanup. Pending jobs are
  left to complete on their own, so lease/cleanup guarantees are not honored at
  the moment dispatch returns.

Read the class docstring in `/app/dispatcher.py` and honor it exactly.

## Step 1 — reproduce

A supplied evaluator lives at `/app/tests/test_contract.py`. Run:

```
pytest -q /app/tests/test_contract.py
```

You will see failures, especially the *concurrency cap is exceeded* test. Read
each failure carefully to understand exactly what contract is being violated.

## Step 2 — fix `dispatch`

Rewrite `Dispatcher.dispatch` in `/app/dispatcher.py` so that:

1. **Concurrency limit is honored.** At most `max_concurrency` jobs run
   concurrently. Wrap each job so it acquires the semaphore and holds one lease
   from `self.leases` for its whole lifetime. Use `LeasePool.hold()` (already
   provided) as an async context manager.
2. **Awaits every job body under the cap.** Each coroutine runs inside an
   `async with self.leases.hold():` (and the semaphore) so the lease is released
   in a `finally`-like manner on success, exception, or cancellation.
3. **Cleanup on failure / Cancellation.** If any job raises, or if the dispatch
   task itself is cancelled (`asyncio.CancelledError` — a `BaseException`, not
   a regular `Exception`), cancel every job that has not yet finished and
   `await` them (e.g. `asyncio.gather(..., return_exceptions=True)`) so their
   cleanup runs, then **re-raise** the original error/cancellation. After
   dispatch returns (or raises), `self.leases.live` must be `0` and no job may
   still be running.

Keep the public API `Dispatcher(max_concurrency)` and `async dispatch(coros)`
exactly as is. Preserve result ordering (results correspond, position-by-position,
to the input coroutines).

## Step 3 — add your own race/stress tests

Create `/app/tests/test_behavior.py` and write your own pytest tests that:

- Verify the concurrency cap is never exceeded, by running a batch of jobs that
  observe peak concurrency, for several limits.
- Verify lease cleanup on **normal completion**, on a **job raising**, and on
  the dispatch task being **cancelled mid-flight**.
- **Repeatedly** run the same cancellation/race scenario several times
  (e.g. 5–10 runs) and assert the invariants hold every time.

These may overlap the supplied evaluator's checks, but must be your own code.

## Success criteria

- `/app/tests/test_contract.py` passes (`pytest -q` with exit 0).
- `/app/tests/test_behavior.py` exists and passes.
- `Dispatcher.dispatch` behaves correctly regardless of order/failure/cancel.
- No warnings about "Task was destroyed", and no unhandled `CancelledError`.