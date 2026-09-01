# Fixed-window rate limiter

`/app/requests.json`:

```json
{
  "config": {"limit": 3, "window_sec": 10},
  "requests_ts": [0.5, 1.2, 1.8, 4.0, 9.5, 10.1, 10.5, 11.0]
}
```

Write `/app/rate_limiter.py` implementing a **fixed-window** rate limiter. Process the
timestamps in the order given; for each request decide allowed/blocked:

- a request is **allowed** if, in its window, fewer than `limit` requests have already
  been allowed;
- otherwise it is **blocked**.

The window of a timestamp `t` is the integer `floor(t / window_sec)` (requests from
the same window share a counter that resets only when the window index changes).

Write `/app/result.json`:

```json
{"allowed": [true, true, true, false, false, true, true, true]}
```

Run `python3 /app/rate_limiter.py` so the file is produced. The verifier recomputes
the boolean sequence from the same input using the same rule; do not hardcode.