# Schedule the cello-harbor live-audio relay

You are the scheduler for **cello-harbor**, a live concert audio relay. A
streaming front-end hands you a log of audio chunks in strict arrival order;
you must bundle them into **segments** (the aligned transmission units) and
group those segments into **broadcast windows** under hard cost, latency, and
granularity constraints, then write the schedule as JSON.

## Environment

- Working directory: `/app`. It already contains the input file
  `/app/stream.json`. Python 3.12 is available as `python3`.
- **Do not modify `/app/stream.json`.**

## Deliverables (both required)

1. `/app/solve.py` — a runnable Python program with this interface:
   ```
   python3 /app/solve.py <stream_json> <output_json>
   ```
   It reads a stream description and writes a schedule JSON to the given
   output path. It must work on **any** input conforming to the contract
   below, not just the provided fixture.

2. `/app/plan.json` — the schedule your program produces **when run on the
   provided `/app/stream.json`**:
   ```
   python3 /app/solve.py /app/stream.json /app/plan.json
   ```

## Input format

`stream_json` holds:
```json
{
  "budget": {"sector": int, "max_segment_ms": int, "window_ms": int, "windows": int},
  "chunks": [{"id": str, "ms": int, "due": int}, ...]
}
```

- `chunks` is the streaming request log **in strict arrival order**.
- `ms` is the chunk's duration in milliseconds; every `ms` is already a
  positive multiple of `budget.sector` (so a valid schedule always exists).
- `due` is the latest broadcast-window index (0-based) in which the chunk may
  be transmitted; a chunk in window `p` requires `p <= due`.

## Required output JSON

Write exactly this shape:
```json
{
  "budget": {"sector": ..., "max_segment_ms": ..., "window_ms": ..., "windows": ...},
  "windows": [
    {"window_id": "<unique str>", "ms": <int>,
     "segments": [
       {"segment_id": "<unique str>", "chunks": [<chunk ids>], "ms": <int>}
     ]}
  ]
}
```
`budget` must be copied through unchanged. `windows` is ordered (window 0 is
the earliest broadcast). Any id strings are fine as long as they are unique.

## Hard constraints (ALL must hold simultaneously)

1. **Order preservation** — reading the chunk ids of `windows[0].segments[0]`,
   then `windows[0].segments[1]`, ..., across all windows in order, must yield
   exactly the input `chunks` id sequence: every id appears **exactly once**
   (none duplicated, none missing) and relative arrival order is preserved
   (no reordering).
2. **Granularity/alignment** — every segment's `ms` (the sum of its chunks'
   `ms`) must be a **positive multiple of `budget.sector`**
   (`ms % sector == 0`).
3. **Segment cap (cost)** — every segment's `ms` must be `<= budget.max_segment_ms`.
4. **Window cap (latency)** — every window's `ms` (sum of its segments) must
   be `<= budget.window_ms`. Every window must hold at least one segment.
5. **Window count** — the total number of windows must be `<= budget.windows`.
6. **Deadlines** — each chunk must be scheduled in a window whose index
   (0-based) is `<=` that chunk's `due`.

Any schedule satisfying all six constraints is accepted; there is no single
"best" arrangement. Chunks must not be split: each whole chunk goes into
exactly one segment.

## Edge cases the grader probes with hidden inputs

- **Empty stream** (`chunks == []`): the plan must have `"windows": []` and
  must not crash.
- **A single chunk** whose `ms` equals both `sector` and `max_segment_ms`.
- **Deadline pressure**: a chunk with a small `due` arriving after earlier
  chunks — earliest-possible assignment keeps it feasible.
- **Cap pressure**: `window_ms` forcing a window break even when a segment
  could still grow, and `max_segment_ms` forcing a segment break mid-window.
- **Odd granularity**: `sector` values like 7 or 12 (not round decimal
  numbers).

## Constraints

- The verifier runs your program **unchanged** (`python3 /app/solve.py`) on
  hidden inputs that follow the same contract — do not hard-code the visible
  fixture's contents or filenames.
- Deterministic, standard library only, no network access.
- Do not modify `/app/stream.json`.
