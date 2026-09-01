# Tide-gauge sonar — recover the seabed depth through a prefix oracle

The oceanography bench at `/app` hosts a **tide gauge** whose sediment column
depth is unknown. The column is not readable as a file: the only way in is the
probing instrument `/app/bin/gauge`, which exposes exactly two endpoints:

```
/app/bin/gauge <ctx> wet <k>     # prints 1 if column position k is still
                                 # submerged (0 <= k < L), else 0
/app/bin/gauge <ctx> core <k>    # prints "core-<k>-<L>" if 0 <= k < L,
                                 # else "BEDROCK"
```

`<ctx>` is a station context file (shipped: `/app/fixtures/station.json`; the
verifier will point the tool at hidden context files with **different**
columns). The depth `L` is a derived property of the station context — it is
**not** the file's line or byte count, and only the instrument can tell you
whether a position exists. Positions `0..L-1` are submerged; everything at and
beyond `L` is bedrock, so `wet` is a monotone prefix predicate and `L` can be
found by binary search — but you are on a **strict budget**.

## Deliverables

1. `/app/sonar.py` — your debugger, invoked as:

   ```
   python3 /app/sonar.py <ctx> [depth_out] [probes_out]
   ```

   It must probe `/app/bin/gauge` (call it as a subprocess; the only supported
   interface is the two endpoints above), determine `L`, and write:

   - `depth_out` (default `/app/depth.txt`): the detected depth — a single
     non-negative integer, newline-terminated, nothing else.
   - `probes_out` (default `/app/probes.json`): the debugging transcript:

     ```json
     { "answer": 1436, "calls": 24, "budget": 28,
       "problem": "tide-gauge-depth",
       "probes": [ {"endpoint": "wet", "k": 2048, "reply": "0"}, ... ] }
     ```

2. `/app/depth.txt` and `/app/probes.json` — the artifacts produced by running
   your tool on the shipped context:

   ```
   python3 /app/sonar.py /app/fixtures/station.json
   ```

## The budget (hard)

- `L` is between 1 and 2999 inclusive.
- You may make **at most 28 instrument calls total per run**. A linear scan
  over thousands of positions blows the budget; exponential bracketing plus
  binary search fits comfortably.
- `calls` in the transcript must equal the number of objects in `probes`,
  must count **every** instrument call you made, and must be `<= budget`.

## Transcript requirements

- `probes` must contain every call you made, in order, each with the endpoint
  used (`"wet"` or `"core"`), the integer `k`, and the exact reply string.
- Both endpoints must appear at least once across the transcript: use `core`
  to confirm the boundary (position `L` must answer `BEDROCK`).
- `answer` must equal the value written to `depth.txt` and the true depth.

## Hidden cases

The verifier re-runs `/app/sonar.py` on hidden station contexts (small,
medium, and near-maximum depths) through the exact interface above and checks
the detected depth, the budget, and the transcript on each.

## Constraints

- Do not modify `/app/bin/gauge`, `/app/fixtures/station.json`, or anything
  else shipped in `/app` besides your own deliverables.
- Python 3.12 standard library only; no network at verify time.
- Do not read `/tests` (it is not present during your work anyway).
