# Cobalt Wharf — quiz-league score reconciliation

The `Cobalt Wharf` quiz league records what each team **predicted** each round and
what the official **answer key** says. You must build a reusable command-line
program that reconciles the two files round by round and writes a JSON scoring
report. The program must work **on any input** that follows the documented
format below, not just on the provided files.

## Environment

- Working directory: `/app`. It already contains the input files
  `/app/predictions.json` and `/app/answer_key.json`. Python 3.12 is available
  as `python3` (standard library only; no network).
- **Do not modify `/app/predictions.json` or `/app/answer_key.json`.**

## Deliverables (both required)

1. `/app/score_report.py` — a runnable Python program with this interface:
   ```
   python3 /app/score_report.py <predictions_json> <answer_key_json> <output_json>
   ```
   It must read the two JSON files and write the scoring report to the given
   output path. It must work on any inputs conforming to the contract below.

2. `/app/report.json` — the report your program produces **when run on the
   provided `/app/predictions.json` and `/app/answer_key.json`**:
   ```
   python3 /app/score_report.py /app/predictions.json /app/answer_key.json /app/report.json
   ```

## Input format

Both input files are JSON objects mapping **round id** (a JSON string, e.g.
`"1"`, `"r2"`) to an object mapping **question id** (a JSON string) to a
**value**. A value is either

- a **real number** (JSON int or float — but **not** a boolean), or
- an **invalid marker**: the string `"ERR"`, or any non-numeric JSON value
  (`null`, `true`/`false`, a string other than numbers, an array, an object).

The two files need not contain the same rounds or the same question ids.

## Reconciliation rules

For each round id that appears in **either** input file:

- A question id is a **candidate pair** only if it appears in **both** the
  prediction object and the key object for that round. Ids present on only one
  side are **unmatched and ignored entirely** (they count nowhere).
- A candidate pair is **invalid** (dropped) if **either** side's value is an
  invalid marker (as defined above). Dropped pairs count toward neither
  `correct` nor `total`.
- A surviving pair counts toward `total`; it is **correct** when the two values
  are an **exact numeric match** (`4` and `4.0` match; `2` and `3` do not).
- `accuracy` = `correct / total` rounded **half-up** to 3 decimal places, where
  half-up means `floor(x * 1000 + 0.5) / 1000` (e.g. `2/3 -> 0.667`,
  `1/16 -> 0.063`). If `total == 0`, the round's `accuracy` is `null`.

## Required output JSON

The output file must be valid JSON with exactly these keys:

```json
{
  "rounds": {
    "<round id>": {"correct": <int>, "total": <int>, "accuracy": <float|null>},
    ...
  },
  "totals": {"correct": <int>, "total": <int>, "accuracy": <float|null>}
}
```

- `rounds` has one entry per round id present in either input (all of them,
  even rounds with zero candidate pairs).
- `totals.correct` / `totals.total` are the sums of the per-round values over
  all valid pairs; `totals.accuracy` is that ratio rounded half-up to 3
  decimals, or `null` when `totals.total == 0`.

## Edge cases the program must handle

These are probed by the grader's hidden inputs, so the program must be correct
on all of them:

- Rounds with **no candidate pairs** (id on one side only, or both objects
  empty / all-invalid) → `accuracy` is `null`, not `0.0` or an error.
- Invalid markers on either side (`"ERR"`, `null`, booleans, arrays, objects,
  non-numeric strings) drop the pair.
- Unmatched ids on either side are ignored entirely.
- **Half-up ties**: e.g. 1 correct out of 16 → `0.063` (not `0.062`), 2/3 →
  `0.667`.
- Exact numeric match across int/float (`4` vs `4.0` is correct; `4` vs `4.1`
  is not).
- Both input files completely empty objects → `"rounds": {}` and
  `"totals": {"correct": 0, "total": 0, "accuracy": null}`.

## Constraints

- The verifier runs your program **unchanged** (via `python3
  /app/score_report.py`) on hidden inputs that follow the same format, so do
  not hard-code to the provided file contents or filenames.
- No network access at verify time; standard library only.
- Do not modify `/app/predictions.json` or `/app/answer_key.json`.
