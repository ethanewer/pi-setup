# Single-server FIFO queue simulation

`/app/workload.json` describes a small set of jobs for a single CPU that processes jobs
one at a time in **first-in-first-out (FIFO)** order. Your job is to write a Python script
`/app/simulate.py` that reads `/app/workload.json`, simulates the queue, and writes the
resulting schedule to `/app/schedule.json`.

## Input file: `/app/workload.json`

A JSON object with:
- `rate` (integer ≥ 1): tokens processed per unit of time. A job carrying `T` tokens
  takes `duration = max(1, ceil(T / rate))` time units.
- `jobs`: an array of `{"id": <int>, "arrival": <int>, "tokens": <int>}`.
  `id` values are unique. A job is available for scheduling at exactly its `arrival` time.

## Simulation rules (deterministic)

1. Only one job runs at a time. Start at time `t = 0` with an empty queue.
2. Repeatedly:
   a. Enqueue every not-yet-scheduled job with `arrival <= t`, in ascending
      `(arrival, id)` order (keep the queue sorted so the oldest arrives first; ties by
      lower `id`).
   b. If the queue is empty, set `t` to the smallest `arrival` among all not-yet-scheduled
      jobs and repeat from (a).
   c. Otherwise take the front job (`start = t`), compute
      `finish = t + max(1, ceil(tokens / rate))`, schedule it, set `t = finish`, and repeat
      until every job is scheduled.

Jobs that arrive *during* a running job are added to the queue at the next decision point.

## Output file: `/app/schedule.json`

```
{
  "jobs": [
    {"id": <int>, "arrival": <int>, "tokens": <int>,
     "start": <int>, "finish": <int>, "wait": <int>}
  ],
  "metrics": {
    "makespan": <int>,        // finish of the last scheduled job
    "total_tokens": <int>,
    "total_jobs": <int>
  }
}
```

`jobs` must contain every input job exactly once, in ascending `id` order. `wait =
finish - arrival`. `metrics.makespan` equals the largest `finish`.

Write `/app/simulate.py`, run it, and leave both `/app/simulate.py` and
`/app/schedule.json` in place when finished. The same input must always produce the same
output (deterministic).