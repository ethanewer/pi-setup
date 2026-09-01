# Aggregate a live tip-jar pulse stream

A livestream tip jar emits a JSON Lines pulse feed. You must build a reusable
command-line program that replays the feed and writes a JSON report tallying,
per tag, the number of tips and the **rounded** total amount. The program must
work **on any input** that follows the documented format below, not just on the
provided file.

## Environment

- Working directory: `/app`. It already contains the input file
  `/app/pulse.jsonl`. Python 3.12 is available as `python3`.
- **Do not modify `/app/pulse.jsonl`.**

## Deliverables (both required)

1. `/app/solve.py` — a runnable Python program with this interface:
   ```
   python3 /app/solve.py <input_jsonl> <output_json>
   ```
   It reads the pulse feed and writes the report to the given output path. It
   must work on any feed conforming to the contract below.

2. `/app/answer.json` — the report your program produces **when run on the
   provided `/app/pulse.jsonl`**:
   ```
   python3 /app/solve.py /app/pulse.jsonl /app/answer.json
   ```

## Input format

`input_jsonl` is a UTF-8 text file with one JSON value per line. Each line is
in exactly one of these categories:

- **Valid tip:** a JSON object with a `"tag"` field that is a string and an
  `"amount"` field that is a number (integer or fractional, possibly negative
  e.g. a refund). Extra fields are allowed and ignored.
- **Skipped:** everything else — a line that is not valid JSON, a JSON value
  that is not an object (e.g. `[1,2,3]` or `7` or `"x"`), an object missing
  `"tag"` or `"amount"`, a non-string `"tag"`, or a non-numeric `"amount"`
  (e.g. a string or `null`).

Blank or whitespace-only lines are ignored entirely and are **not** counted as
skipped.

## Required output JSON

The output file must be valid JSON with exactly these keys:

```json
{
  "tips": <int>,
  "skipped": <int>,
  "tags": {
    "<TAG>": {"count": <int>, "amount": <float>},
    ...
  }
}
```

- `tips` = total number of valid tips (across all tags).
- `skipped` = number of skipped lines (blank lines excluded).
- One entry in `tags` per distinct tag with **at least one** valid tip.
- `tags[<TAG>]["count"]` = number of valid tips for that tag (an **int**).
- `tags[<TAG>]["amount"]` = the sum of that tag's amounts, **rounded to
  exactly 2 decimal places and serialized as a JSON float** (so `10` must be
  written as `10.0`, never `10`), e.g. `9.6`.

## Edge cases the program must handle

These are probed by the grader's hidden inputs, so the program must be correct
on all of them:

- **Floating-point drift:** sums like `0.1 + 0.2` must be reported as `0.3`
  after rounding — never as `0.30000000000000004`.
- **Integral sums** must still be floats: a tag whose amounts sum to exactly
  `10` must be reported as `10.0` (a JSON float), not `10` (an integer).
- **Multiple tips per tag** are summed, including fractional-cent amounts that
  require the final rounding step.
- **Skipped lines** of every category above must increment `skipped` without
  contributing to `tips` or `tags`.
- **Blank lines** are ignored and not counted in `skipped`.
- **An empty file (zero lines):** `tags` must be `{}`, `tips` must be `0`, and
  `skipped` must be `0`.
- **A file with only skipped lines:** `tags` must be `{}` and `tips` `0`, but
  `skipped` must equal the number of lines.

## Constraints

- The verifier runs your program **unchanged** (via `python3 /app/solve.py`) on
  hidden inputs that follow the same format, so do not hard-code to the
  provided file contents or filenames.
- No network access at verify time; standard library only.
- Do not modify `/app/pulse.jsonl`.
