# Score a quiz league by round accuracy

You must build a reusable command-line scorer for a quiz league and produce one
report. The program must work **on any input** that follows the documented
format below, not just on the provided files.

## Environment

- Working directory: `/app`. It already contains the input files
  `/app/model.json` (a contestant's submitted answers) and `/app/key.json`
  (the official answer key). Python 3.12 is available as `python3`.
- **Do not modify `/app/model.json` or `/app/key.json`.**

## Deliverables (both required)

1. `/app/score.py` — a runnable Python program with this interface:
   ```
   python3 /app/score.py <model_json> <truth_json> <output_json>
   ```
   It reads the two answer files and writes the round report to the given
   output path. It must work on any inputs conforming to the contract below.

2. `/app/report.json` — the report your program produces **when run on the
   provided `/app/model.json` and `/app/key.json`**:
   ```
   python3 /app/score.py /app/model.json /app/key.json /app/report.json
   ```

## Input format

Both input files are JSON objects mapping **round id** (a JSON string, e.g.
`"R1"`) to an object mapping **question id** (a JSON string) to a **value**.
A value is either:

- a **number** (JSON integer or float), or
- the string `"ERR"` — the error / invalid marker (the contestant
  abstained, or the key marked the question void).

A question id is a **candidate pair** for a round if it appears in **both**
the model's round object and the truth's round object for that round id.
Question ids that appear on only one side are **unmatched and ignored
entirely** — they never count toward `correct` or `total`.

A candidate pair is **invalid** (dropped) if either side's value is `"ERR"`
(or any non-numeric value). Dropped pairs do not count anywhere.

A surviving (valid) pair counts toward `total` for that round, and counts
toward `correct` exactly when the two values are **numerically equal**
(comparing by value: JSON `4` and `4.0` are equal; no tolerance, no rounding
of inputs).

## Required output JSON

The output file must be valid JSON: an **array**, sorted by round id using
plain string sort, with one entry per round id that appears in **either**
input file (even a round present only on one side, or a round with no valid
pairs):

```json
[
  {"round": "R1", "correct": 2, "total": 3, "accuracy": 0.667},
  {"round": "R2", "correct": 0, "total": 0, "accuracy": null}
]
```

- `correct` and `total` are integers.
- `accuracy = correct / total` rounded **half-up** to 3 decimal places, where
  half-up is `floor(x * 1000 + 0.5) / 1000` clamped to `[0, 1]` (so `2/3`
  becomes `0.667` and `1/8` becomes `0.125`).
- If `total == 0` (no valid pairs for the round), `accuracy` is `null`.
- If both input files are empty objects, the output is `[]`.

## Edge cases the program must handle

These are probed by the grader's hidden inputs, so the program must be
correct on all of them:

- `"ERR"` on the model side only, on the truth side only, and on both sides —
  all such pairs are dropped.
- Unmatched question ids on either side — ignored entirely.
- A round whose candidate pairs are all invalid — `correct: 0, total: 0,
  accuracy: null`.
- A round present in only one of the two files — still reported (with the
  pairs it has; likely `total: 0`).
- Half-up rounding ties: `2/3 -> 0.667`, `1/8 -> 0.125`, `1/1 -> 1.0`.
- Integer vs float equality across sides (`4` vs `4.0` is a correct pair).
- Round ids sorted as strings (e.g. `"R10"` sorts before `"R2"`).

## Constraints

- The verifier runs your program **unchanged** (via `python3 /app/score.py`)
  on hidden inputs that follow the same format, so do not hard-code to the
  provided file contents or filenames.
- No network access at verify time; standard library only.
- Do not modify `/app/model.json` or `/app/key.json`.