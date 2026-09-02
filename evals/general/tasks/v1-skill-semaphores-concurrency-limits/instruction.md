# skill-semaphores-concurrency-limits — cap concurrent work with a semaphore

This environment is a blank Python harness. Your only task is to demonstrate a
**concurrency limit** with `threading.BoundedSemaphore`.

Write `/app/limited.py` that:

1. Creates a `threading.BoundedSemaphore(4)`.
2. Launches **30 worker threads**.
3. Each worker, inside the semaphore guard, does a tiny amount of work and
   sleeps briefly (e.g. `time.sleep(0.02)`), then releases the slot.
4. Uses a lock-protected global counter and a separate `max_concurrent`
   tracker so it can measure the **peak number of workers inside the guard at
   any one instant** (a `current` counter, bumped on acquire and decremented on
   release, and `peak = max(peak, current)`).
5. Waits for all threads, then writes `/app/result.json`:
   ```json
   { "limit": 4, "total": 30, "completed": 30, "peak": 4 }
   ```

The point is the **concurrency limit**: with 30 workers and a semaphore of
size 4, at most 4 may ever be inside the guard at once, and because there are
more workers than slots, the observed `peak` will actually **equal** the limit
(4). (If you did *not* limit it, `peak` would be 30.)

## Success criteria

The verifier runs `/app/limited.py` and checks that the produced
`/app/result.json` has:
- `completed == total` (all 30 workers actually ran),
- `1 <= peak <= limit`,
- `peak == limit` (the bound was genuinely binding).

Do not change `limit`/`total` — they are fixed at 4 and 30 by the contract.