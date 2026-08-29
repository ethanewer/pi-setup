# zephyr-grove — Scheduling & Arrangement Engine

A venue collects availability and number-workforce data into a single JSON
config and needs a repeatable scheduling engine. You must write **one
executable Python program** at `/app/solver.py` that reads such a config and
produces exactly three output files. The grader re-runs your program on fresh
configs, so it must be generic and deterministic. Only the Python standard
library is required (no external packages needed); `scipy` is also installed.

## Deliverables

Write an executable program at `/app/solver.py`:

```
python3 /app/solver.py <config.json> <outdir>
```

- `<config.json>` — a JSON scheduling config (see *Config schema*). Passed on
  the command line; you must **not** assume or hard-code a fixed path.
- `<outdir>` — the directory to write outputs into. Create it if it does not
  exist.
- On **every** run the program must write three files into `<outdir>`:
  `answer.txt`, `grid.txt`, and `plans.txt`.

You must also actually run your program on the shipped config at
`/app/config.json` writing into `/app`, so that the deliverables
`/app/answer.txt`, `/app/grid.txt`, and `/app/plans.txt` exist at their
required paths:

```
python3 /app/solver.py /app/config.json /app
```

Do **not** modify `/app/config.json`.

## Config schema

The config JSON has these keys (all optional; defaults below). A syntactically
valid JSON object is always supplied, but individual fields may be unusual or
malformed, as listed.

| key               | meaning                                                            |
|-------------------|--------------------------------------------------------------------|
| `allowed`         | list of integer values in the work pool (may repeat, may include      non-positive values) |
| `target_sum`      | integer target sum                                                   |
| `business_start`  | start of the weekday business-hours window, in minutes from 00:00  |
| `business_end`    | end of that window, in minutes (exclusive)                         |
| `lunch_start`     | start of the excluded lunch window, minutes                        |
| `lunch_end`       | end of the excluded lunch window, minutes                          |
| `duration_needed` | minimum free-window length in minutes that still counts            |
| `busy`            | object mapping a person's name to a list of `[start, end]` busy intervals (minutes) |

Default values (used only when a field is missing): `business_start=540`,
`business_end=1020`, `lunch_start=720`, `lunch_end=780`, `duration_needed=30`,
`allowed=[]`, `target_sum=0`, `busy={}`.

## Output 1 — `answer.txt` (feasible-combination total)

Count how many **distinct subsets** of `allowed` sum exactly to `target_sum`.
This respects two constraints: every chosen number must come from `allowed`
(only allowed numbers), and no element may be used more than once (one-use-only).

Counting rules:

- Each element of `allowed` is a **distinct** item even if its value repeats
  (so a list with two `1`s can choose the first, the second, or both — those
  are different subsets).
- Positive integers only participate. Non-positive values are ignored entirely.
- The count is by element position (a subset), not by value.
- If `target_sum < 0`, the answer is `0`. If `target_sum == 0`, the empty
  subset is exactly one way.
- If no subset reaches the target, the answer is `0`.
- Example: `allowed=[3,5]`, `target_sum=8` → the only subset is `{3,5}` → answer
  `1`. `allowed=[4,7,9]`, `target_sum=100` → no subset reaches it → `0`.

Write the integer as **plain text**: nothing before or after it, and **no
trailing newline** (the file must contain only the digits, e.g. `17`).

## Output 2 — `grid.txt` (9x9 arrangement)

Produce a solved **9x9 arrangement**: a Latin square of order 9, i.e. a 9-by-9
grid where every row and every column is a permutation of the allowed digits
`1..9` (each value used exactly once per row and once per column — again
one-use-only, from the allowed set `{1..9}`).

Format (strict):

- exactly **9 lines** (a trailing newline after the last line is permitted);
- each line holds exactly **9 tokens** separated by single spaces;
- every token is a **two-digit, zero-padded** integer in `01..09` (row-major
  order — this is the canonical two-digit-tile representation).
- no other text.

Any valid 9x9 Latin square over the digits `1..9` in that format is accepted;
the exact square you choose does not matter, but it must be a correct solved
grid. Example first line: `01 02 03 04 05 06 07 08 09` (a valid row).

## Output 3 — `plans.txt` (availability overlap results)

A minute `m` (an integer, minutes from 00:00) counts as **available** when **all**
of these hold:

- `business_start <= m < business_end` (inside the weekday business-hours
  window), and
- NOT `lunch_start <= m < lunch_end` (outside the lunch window), and
- for **every** person in `busy`, `m` is not inside any of that person's
  `[start, end)` busy intervals (simultaneous multi-person availability).

Interval semantics:

- A busy interval `[s, e]` covers minutes `m` with `s <= m < e`.
- Intervals with `e <= s` are malformed and occupy nothing — ignore them.
- An entry in `busy` that is not a list of intervals (e.g. a string, `true`,
  or a single number) is malformed — ignore that person entirely.
- Overlapping intervals are fine; availability is their union.

Now scan the minutes `business_start .. business_end-1`. A **run** is a maximal
contiguous block of available minutes. You report a window for a run only when
its length is **at least `duration_needed`** minutes (boundary exact-equal is
included). Write to `plans.txt` JSON with exactly this structure:

```json
{
  "business": { "start": "08:00", "end": "18:00" },
  "lunch":    { "start": "13:00", "end": "14:00" },
  "duration_needed": 30,
  "windows": [
    { "start": "08:00", "end": "08:30" },
    { "start": "10:00", "end": "13:00" }
  ]
}
```

- `business.start`/`end` and `lunch.start`/`end` are the window boundaries as
  `HH:MM` (24-hour, zero-padded).
- `duration_needed` is the integer requirement from the config.
- `windows` lists each qualifying maximal run in **start-time order**; each
  entry has `start` (HH:MM at the run's first minute) and `end` (HH:MM at the
  minute just past its last minute). `end` is exclusive. `start` is inclusive.
- If no run reaches `duration_needed`, `windows` is `[]`. Run maxima are
  maximal free blocks — a run that the lunch window slices into two is reported
  as two separate windows (one on each side), not merged.

Minutes -> `HH:MM`: hour = `m // 60`, minute = `m % 60`, both zero-padded
(0..23, 0..59).

## Constraints and verification

- Write real code that computes these from the config on every run; do not
  hard-code numbers for the shipped config. The grader re-runs `/app/solver.py`
  on unseen configs with the same schema and checks all three outputs against
  independent recomputation.
- Keep `grid.txt`, `answer.txt`, and `plans.txt` in `<outdir>` exactly as
  specified, at exactly the paths above.
- The program only needs the standard library.
- Edge behaviors the grader probes include: a target that no subset reaches
  (answer `0`), an all-busy day (empty `windows`), a lunch window that slices a
  gap and a run whose length is exactly the duration boundary (both counted),
  duplicate and non-positive numbers in `allowed`, and malformed `busy` entries
  — make sure your program handles all of these without crashing and with the
  documented results.