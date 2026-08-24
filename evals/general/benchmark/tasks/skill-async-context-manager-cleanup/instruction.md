# Async context-manager cleanup

`/app/cleanres.py` defines an asynchronous class `Managed` that is used with the `async with` statement. It is designed so that every time an `async with` block exits — **including when the body raises an exception** — the `__aexit__` method guarantees that cleanup runs and records it by writing the literal text `cleaned` to a marker path.

Read `/app/cleanres.py`. Then write `/app/solve.py` that:

1. Imports `Managed` from `cleanres` (run from `/app`; add `/app` to `sys.path` if needed).
2. Uses `async with Managed('/app/cleaned.txt')` inside an `asyncio` coroutine.
3. Inside the `async with` body it deliberately raises `ValueError("boom")` to simulate a failure mid-session.
4. The block is wrapped in `try/except ValueError` so the exception is handled and the program exits cleanly.

The key requirement: **the `__aexit__` cleanup must always run**, so after the program runs, `/app/cleaned.txt` must exist and contain exactly `cleaned` — proving the cleanup path executed despite the exception in the body. (`Managed.__aexit__` already returns `False`, i.e. it never suppresses the exception, and it always performs its file write.)

Run it as `python3 /app/solve.py`.