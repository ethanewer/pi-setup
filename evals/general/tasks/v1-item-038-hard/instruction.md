# Fairness-aware batch scheduler for an inference pool

You are implementing the dispatch scheduler for a small GPU inference pool. A fixed
workload arrives over time, one JSON input file at `/app/workload.json`. Your job is to
read the operator's *prose scheduling rules* below, translate them into exact invariants,
and implement a **deterministic discrete-event simulator** in Python that produces the
complete schedule and an audit report.

## Input file: `/app/workload.json`

A JSON object with these fields:

- `capacity` (integer ≥ 1): the **maximum total tokens** a batch may carry. A batch may
  never exceed this, and every single request's tokens is ≤ `capacity`.
- `rate` (integer ≥ 1): tokens processed per unit of time. A batch that carries `T` tokens
  takes `max(1, ceil(T / rate))` time units.
- `shapes`: the static shape-compatibility graph. Each element is `{"id": <int>, "compatible": [<int>, ...]}`.
  The listed ids are shapes that may share a batch with this shape. **Interpret the graph
  as undirected**: if shape `a` lists `b`, then `b` also counts as compatible with `a`,
  even if `b`'s own list is asymmetric (a request of one shape may batch with a request of
  the other either way). A shape is always compatible with itself. Two shapes that are not
  connected by any path of length 1 are **conflicting**: they may never be in the same batch.
- `requests`: the workload. Each element is
  `{"id": <int>, "arrival": <int>, "shape": <int>, "tokens": <int>, "deadline": <int>}`.
  `id` values are unique. `arrival` is the integer time the request joins the queue
  (it is available for scheduling at exactly that time). `deadline` is soft-accounting
  only — it never blocks or changes the schedule, and violating it is not an error,
  but it must be tracked.

## The scheduler's operational rules (operator prose — translate these into invariants)

1. **One server.** There is a single GPU. It processes at most one batch at a time, and
   it never idles while the queue is non-empty. The first batch starts at time `0` if any
   request is queued at time `0`.

2. **Fairness, no overtaking.** No queued request may be overtaken by a request that
   arrived later. Concretely: whenever a batch is composed, the batch's oldest member —
   the request with the smallest `(arrival, id)` among **all** queued requests — must be in
   that batch. All tie-breaks use the smallest `(arrival, id)` (lower `id` first).

3. **Batch shaping (shape-aware batching).** A batch is built greedily from the queued
   requests, as follows:

   a. Let `L` be the oldest queued request (rule 2). Only requests whose shape is
      compatible with `L`'s shape (per the undirected graph inferred from `shapes`) are
      candidates for this batch.
   b. Walk the candidates sorted by `(arrival, id)`. Keep a request in the batch if
      **both** hold: (i) its shape is compatible with the shape of *every* request already
      in the batch (i.e. the batch's shape set must be pairwise compatible — conflicting
      shapes can never share a batch, even if both are compatible with `L`), and (ii) its
      `tokens` still fit in the remaining `capacity` (cumulative tokens must stay ≤
      `capacity`).
   c. If no candidate fits (should not happen for well-formed data — `L` alone always
      fits), the batch is `L` alone.

4. **Time model.** The batch starts at the current time `t` (an integer). It finishes at
   `t + duration` where `duration = max(1, ceil(total_tokens / rate))`. Requests that
   arrive at any time during the batch join the queue and are scheduled at the *next*
   decision point. The next batch starts exactly when the previous one finishes; if the
   queue is empty the server time-travels to the next arrival (the schedule still records
   integer start times).

## Deliverables (write these files)

### 1. `/app/schedule.json` — the full schedule

```json
{
  "batches": [
    {"start": <int>, "finish": <int>, "duration": <int>, "requests": [<id>, ...]}
  ],
  "requests": [
    {"id": <int>, "shape": <int>, "arrival": <int>, "tokens": <int>,
     "deadline": <int>, "start": <int>, "finish": <int>, "wait": <int>,
     "late": <bool>}
  ],
  "metrics": {
    "makespan": <int>,                     // finish of the last batch (>= 1 if any request)
    "mean_wait": <float>,                  // mean of (finish - arrival), 6 decimal places
    "max_wait": <int>,                     // max of (finish - arrival)
    "deadline_misses": <int>,              // count of requests with finish > deadline
    "throughput_tokens_per_time": <float>, // round(total_tokens / makespan, 6)
    "total_requests": <int>,
    "total_tokens": <int>
  }
}
```

`requests` contains **every** request from the input, in ascending `id` order, each
exactly once. `wait = finish - arrival`. `late = finish > deadline`. `batches` is in
schedule order.

### 2. `/app/audit.json` — boundary-case audit of *your own* schedule

Your simulator must also verify its own output against these four invariants and report
booleans:

```json
{
  "checks": {
    "start_not_before_arrival": <bool>,
    "single_server_contiguous": <bool>,   // batches never overlap and start back-to-back
    "all_served_exactly_once": <bool>,    // every id present once in requests[], one batch
    "capacity_respected": <bool>          // every batch total tokens <= capacity
  },
  "passes": <bool>                         // all four checks true
}
```

Compute these by re-scanning the `schedule.json` you produced (they must all be `true` for
a valid implementation of the rules).

## How to work

1. Implement the simulator in `/app/scheduler.py` that reads `/app/workload.json` and
   writes `/app/schedule.json` and `/app/audit.json`.
2. Run it.
3. Sanity-check by hand: print the batches and confirm the batch sequence is legal and
   deterministic (same input ⇒ same output).

There are exactly 7 requests and the workload is sized so your schedule is unique. Leave
`/app/scheduler.py`, `/app/schedule.json` and `/app/audit.json` in place when you are done.