# Concurrent computation with asyncio

Write a Python program `/app/solver.py` that uses **Python's `asyncio`** to run two computations concurrently and aggregate their results.

Define an `async def compute(x)` coroutine that:

- `await asyncio.sleep(0.5)` (simulating I/O-bound work), then
- returns `x * x`.

Your program should:

1. Use `asyncio.gather` to run `compute(4)` and `compute(6)` **concurrently** (created as two tasks / awaited with `gather`), so they overlap in time.
2. Compute `total = 16 + 36` from the gathered results (the two squares).
3. Write `/app/answer.txt` containing exactly:

```
total squares = 52
```

4. Terminate cleanly.

Run `/app/solver.py` so `/app/answer.txt` exists. Because the two `compute` calls overlap, the whole run should take only about `0.5s` (not `1.0s`). The verifier checks the file content and that the run completes quickly (concurrent overlap).

## What to verify
- `answer.txt` content equals `total squares = 52`.
- The recorded wall-clock time of running `/app/solver.py` is under `0.95s` (proving the coroutines ran concurrently, not sequentially).