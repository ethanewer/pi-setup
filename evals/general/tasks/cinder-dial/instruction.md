# Score forecasting tournament rounds

A forecasting tournament records, for every round, what each entrant
predicted and what the ground truth was. Some predictions are marked as
errors (the entrant abstained or the question was voided). You must build a
reusable command-line scorer that reports per-round accuracy — counting only
question ids that appear on **both** sides and only when **neither** side is
an error — and produce one summary. The program must work **on any input**
that follows the documented format below, not just on the provided file.

## Environment

- Working directory: `/app`. It already contains the input file
  `/app/rounds.json`. Python 3.12 is available as `python3`.
- **Do not modify `/app/rounds.json`.**

## Deliverables (both required)

1. `/app/rounds.py` — a runnable Python program with this interface:
   ```
   python3 /app/rounds.py <input_json> <output_json>
   ```
   It reads the combined record file and writes the scoring summary to the
   given output path. It must work on any input conforming to the contract
   below.

2. `/app/answer.json` — the summary your program produces **when run on the
   provided `/app/rounds.json`**:
   ```
   python3 /app/rounds.py /app/rounds.json /app/answer.json
   ```

## Input format

`<input_json>` is a single JSON object with exactly two keys:

```json
{
  "predictions": { "<round>": { "<question>": <value>, ... }, ... },
  "truth":       { "<round>": { "<question>": <value>, ... }, ... }
}
```

- `<round>` is a **decimal integer string without leading zeros** (e.g.
  `"1"`, `"2"`, `"10"`). It need not appear in both sub-objects.
- `<question>` is an arbitrary JSON string question id.
- `<value>` is either a **JSON number** (integer or float) or an
  **invalid marker**: the string `"ERR"`, `null`, a boolean, a string, or
  any other non-number JSON value.

For a given round, a question id is a **candidate pair** if it appears in
**both** `predictions[r]` and `truth[r]`. Question ids present on only one
side are **unmatched and ignored entirely** — they never count anywhere.

A candidate pair is **invalid** (dropped) if **either** side's value is not
a JSON number (including `"ERR"`). Dropped pairs do not count toward
`correct` or `total`.

A surviving pair counts toward that round's `total`, and counts toward
`correct` exactly when the two numbers are **numerically equal** (JSON `4`
and `4.0` are equal; exact numeric match, no tolerance, no rounding of the
inputs).

## Required output JSON

```json
{
  "overall": {"correct": <int>, "total": <int>, "accuracy": <float|null>},
  "rounds": [
    {"round": "1", "correct": <int>, "total": <int>, "accuracy": <float|null>},
    ...
  ]
}
```

- `rounds` contains one entry per round id that appears in **either**
  `predictions` or `truth` (even a round present only on one side, or one
  with no valid pairs), **sorted by the numeric value of the round id
  ascending** (so `"2"` sorts before `"10"` — this is not string order).
- Per-round and overall `accuracy` = `correct / total` rounded **half-up**
  to 3 decimal places, where half-up means
  `floor(x * 1000 + 0.5) / 1000` clamped to `[0, 1]` (so `2/3` becomes
  `0.667` and `1/8` becomes `0.125`).
- When `total == 0` (no valid pairs for that round, or no rounds at all),
  the corresponding `accuracy` is `null`.
- `overall.correct` / `overall.total` sum the surviving valid pairs across
  **all** rounds; with no valid pairs at all, `overall` is
  `{"correct": 0, "total": 0, "accuracy": null}` and `rounds` is `[]` when
  both sub-objects are empty.

## Edge cases the program must handle

These are probed by the grader's hidden inputs, so the program must be
correct on all of them:

- Invalid marker on the predictions side only, on the truth side only, and
  on both sides — all such pairs are dropped.
- Non-number values such as `null`, booleans, or quoted numbers (`"7"`)
  are invalid just like `"ERR"`.
- Unmatched question ids on either side — ignored entirely.
- A round whose candidate pairs are all invalid — `correct: 0, total: 0,
  accuracy: null`.
- A round present in only one of the two sub-objects — still reported.
- Half-up rounding ties: `2/3 -> 0.667`, `1/8 -> 0.125`, `1/6 -> 0.167`.
- Integer vs float equality across sides (`4` vs `4.0` is a correct pair).
- Numeric round-id ordering: `"2"` before `"10"` before `"12"`.
- Both sub-objects empty — `overall` accuracy `null` and `rounds: []`.

## Constraints

- The verifier runs your program **unchanged** (via `python3 /app/rounds.py`)
  on hidden inputs that follow the same format, so do not hard-code to the
  provided file contents or filenames.
- No network access at verify time; standard library only.
- Do not modify `/app/rounds.json`.
