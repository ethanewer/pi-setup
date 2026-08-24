# asyncio task cancellation

`/app/tasklib.py` defines `async def long_task(tag, markers)`, a long-running coroutine that loops forever (sleeping briefly) and, in its `except asyncio.CancelledError` handler, records `markers[tag] = True` before re-raising the cancellation. It lives in `/app`, so add `/app` to `sys.path` if needed.

Write `/app/solve.py` that:

1. Imports and runs `tasklib.long_task`.
2. Creates **two** asyncio tasks (tags `"t1"` and `"t2"`) sharing one `markers` dict (`{}`).
3. Lets them run briefly (`await asyncio.sleep(0.2)`).
4. **Cancels** both tasks with `.cancel()`.
5. Awaits them with `asyncio.gather(..., return_exceptions=True)` so the cancellation is consumed without raising.
6. Writes `/app/cancellation.json`:

```json
{"t1_cancelled": true, "t2_cancelled": true}
```

The booleans must be `true` iff each task's `CancelledError` handler ran (i.e. the task was actually cancelled and its cleanup marker was set). After running `python3 /app/solve.py`, both flags must be `true`.

Use asyncio's `Task.cancel()` plus `gather(..., return_exceptions=True)` — this is the standard pattern for cancelling background tasks and collecting their cancellation.