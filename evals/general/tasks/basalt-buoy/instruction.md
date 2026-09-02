# Plan the basalt-buoy telemetry drain

The **basalt-buoy** ocean sensor relay queues telemetry messages as they arrive
and drains them to a satellite uplink in **transmit batches**, which are grouped
into **radio cycles**. The uplink charges per batch and the radio only accepts
frame-aligned payloads, so the drain must satisfy several constraints at once.
You must write a planner that turns a queue snapshot into a drain plan.

## Environment

- Working directory: `/app`. It already contains the queue snapshot
  `/app/input/requests.json`. Python 3.12 (standard library only) is available
  as `python3`.
- **Do not modify `/app/input/requests.json`.**

## Deliverables (both required)

1. `/app/relay.py` — a runnable planner with this interface:
   ```
   python3 /app/relay.py <requests.json> <plan.json>
   ```
   It reads a queue snapshot and writes the drain plan to the given output
   path. It must work on **any** input conforming to the contract below, not
   only the shipped snapshot.

2. `/app/plan.json` — the plan your planner produces **for the shipped
   snapshot**:
   ```
   python3 /app/relay.py /app/input/requests.json /app/plan.json
   ```

## Input format

`requests.json`:
```json
{
  "budget": {"granule": int, "batch_cap": int, "fanout": int,
             "cycle_cap": int, "cycle_max": int},
  "requests": [{"id": str, "units": int}, ...]
}
```

- `requests` is the stream **in arrival order**; `units` are payload sizes in
  64-byte frames (each `units >= 1`).
- Budget fields: `granule` — frame-alignment quantum; `batch_cap` — maximum
  units per transmit batch; `fanout` — maximum number of messages per batch;
  `cycle_cap` — maximum units per radio cycle; `cycle_max` — maximum number of
  cycles allowed in the whole plan.

## Required plan (output JSON)

```json
{
  "budget": { ...same budget object, echoed unchanged... },
  "cycles": [
    {"cycle_id": "c0", "units": <int>,
     "batches": [
       {"batch_id": "c0-b0", "requests": ["<id>", ...], "units": <int>},
       ...]},
    ...
  ]
}
```

## Hard constraints — ALL must hold

1. **Partition, order-preserving.** Taken in plan order, the batches cut the
   stream into consecutive runs: the messages of the first batch are the first
   `k` requests of the stream, the next batch takes the following run, and so
   on. No reordering, no splitting a message, no message left out.
2. **Exactly-once delivery.** Every request `id` appears exactly once across
   the whole plan (none duplicated, none missing).
3. **Batch cost/latency cap.** Every batch's `units` (sum of its messages'
   units) satisfies `1 <= units <= batch_cap`.
4. **Batch frame alignment (granularity).** Every batch's `units` is a
   **positive multiple of `granule`** (`units % granule == 0`).
5. **Batch fanout.** Every batch contains at most `fanout` messages (at least
   one).
6. **Cycle cost cap.** Every cycle's `units` (sum of its batches' units)
   satisfies `units <= cycle_cap`; every cycle holds at least one batch, and
   batches stay in stream order within and across cycles.
7. **Flight cap.** The total number of cycles is `<= cycle_max`.

Individual message `units` are **not** necessarily multiples of `granule` —
only each *batch total* must be frame-aligned. Batches must therefore be cut at
the right places in the stream. Inputs shipped to your planner are guaranteed
feasible (a plan satisfying all seven constraints exists).

Any plan satisfying all constraints is accepted — there is no unique "best"
plan. The IDs follow the scheme `c<k>` for cycles (in order, starting at
`c0`) and `c<k>-b<m>` for batches (in order within their cycle, starting at
`b0`).

## Edge cases the grader probes with hidden snapshots

- An **empty stream** (`requests: []`): the plan must simply have
  `"cycles": []`.
- A **single message**.
- Snapshots where a naive "keep stuffing the batch until it hits `batch_cap`"
  rule produces a batch whose total is **not** a multiple of `granule` — the
  cut points must respect alignment instead.
- `fanout == 1` (one message per batch).
- Larger streams (hundreds of messages) where cycle packing matters.

## Constraints

- The verifier re-runs `/app/relay.py` unchanged on hidden snapshots, so do
  not hard-code the shipped file's contents or filenames.
- Standard library only; no network access at verify time.
- Do not modify `/app/input/requests.json`.
