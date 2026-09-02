# Find the cancellation-only double-release in the async lease accounting

## Context

`/app/dispatcher.py` has a `Dispatcher` that runs coroutine jobs under a
concurrency cap. Each job holds exactly one "lease" from a `LeasePool` for its
whole lifetime, and that lease must be returned **exactly once** — whether the
job completes, raises, or is cancelled. The provided `LeasePool.hold()` async
context manager already guarantees release-on-exit (its `finally` decrements
once). See the class docstrings.

There is one subtle bug somewhere in `Dispatcher` that makes lease accounting
**wrong only on the abnormal / cancellation path**. You must find it and prove
your fix with tests.

## The symptom

- Gets: normal-completion batches leave `d.leases.live == 0` (correct).
- BUT if **any** job raises, **or the dispatch task is cancelled while jobs are
  still running**, `d.leases.live` goes **negative** (e.g. `-1`, `-2`, ...).
  A lease is momentarily released **twice** for the same job — once by
  `hold()`'s `finally`, once by some spurious extra release.

Reproduce it:

```
pytest -q /app/tests/test_contract.py
```

Focus on `test_cleanup_on_failure_is_exact` and
`test_cancel_is_exact_and_never_negative` — these specifically assert
`live == 0` and `live >= 0` after abnormal finishes, and they fail on the
buggy code because live has gone negative. Read the tracebacks to find the
extra release.

## Your task

1. **Find the extra lease release** that only fires when a job raises or is
   cancelled. It is a *spurious second release* on the abnormal path. Remove it
   (the `LeasePool.hold()` context manager is the single responsible party;
   nothing else may touch `leases._live`).
2. Keep every functional property intact:
   - at most `max_concurrency` jobs run at once (semaphore enforced);
   - results come back in input order;
   - on a job failure or dispatch cancellation, the remaining jobs are
     **cancelled and awaited** so their cleanup runs, then the original
     error / `CancelledError` is re-raised;
   - `self.leases.live` is `0` (never negative) after dispatch returns or
     raises.
3. A goal, `self.leases.live` should never dip below `0` at any point, including
   mid-scenario. Prove it.

## Step 3 — add a race/fuzz test

Create `/app/tests/test_behavior.py` that **repeatedly** (e.g. dozens of runs,
more than the medium task) fires the cancellation path against several
concurrency limits and asserts, every single time, that afterwards
`d.leases.live == 0`, `d.leases.live >= 0` at every observed step, and that no
"Task was destroyed" warnings / unhandled `CancelledError` are emitted. Also
verify the concurrency cap and result ordering.

## Success criteria

- `/app/tests/test_contract.py` passes.
- `/app/tests/test_behavior.py` exists and passes.
- `Dispatcher.dispatch` leaves `live == 0` and `>= 0` on normal, failure, and
  cancellation paths, under repeated runs.