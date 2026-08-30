# Index a mixed-format operations log

You must build a reusable command-line program that indexes an operations log
within an inclusive UTC date range and writes a JSON summary. The program must
work **on any input** that follows the documented format below, not just on the
provided files.

## Environment

- Working directory: `/app`. It already contains the input files
  `/app/operations.log` and `/app/query.txt`. Python 3.12 is available as
  `python3`.
- **Do not modify `/app/operations.log` or `/app/query.txt`.**

## Deliverables (both required)

1. `/app/solve.py` — a runnable Python program with this interface:
   ```
   python3 /app/solve.py <log_file> <query_file> <output_json>
   ```
   It must read a log and a query, and write a JSON summary to the given output
   path. It must work on any log/query conforming to the contract below.

2. `/app/answer.json` — the JSON summary your program produces **when run on the
   provided `/app/operations.log` and `/app/query.txt`**:
   ```
   python3 /app/solve.py /app/operations.log /app/query.txt /app/answer.json
   ```

## Input format

`query_file` is plain text with two lines:
```
from=YYYY-MM-DD
to=YYYY-MM-DD
```
The range `[from, to]` is **inclusive on dates** (UTC). Only log entries whose
UTC calendar date is inside `[from, to]` are included.

`log_file` is newline-separated text. Each line is in exactly one of **three**
categories:

- **Format A:** `YYYY-MM-DDTHH:MM:SSZ SEVERITY OPERATION <N>ms`
  e.g. `2032-02-01T10:00:00Z INFO read 4ms`
- **Format B:** `[YYYY-MM-DDTHH:MM:SSZ] SEVERITY OPERATION duration=<N>`
  e.g. `[2032-02-02T11:00:00Z] WARN write duration=8`
- **Malformed:** any line matching neither Format A nor Format B.

Where:
- `YYYY-MM-DDTHH:MM:SSZ` is a UTC timestamp using a literal `Z` for UTC.
- `SEVERITY` is an all-caps token `[A-Z]+` (e.g. `INFO`, `WARN`, `ERROR`).
- `OPERATION` is a word token `[A-Za-z0-9_]+`.
- The duration is a **non-negative integer** number of milliseconds in both
  formats.

Malformed lines are counted but otherwise ignored.

## Required output JSON

The output file must be valid JSON with exactly these keys:
```json
{
  "average_ms": { "<SEVERITY>/<OPERATION>": <float>, ... },
  "counts":     { "<SEVERITY>/<OPERATION>": <int>,   ... },
  "malformed":  <int>
}
```

- One entry per distinct `<SEVERITY>/<OPERATION>` that has **at least one**
  in-range log entry. Out-of-range entries do not create keys.
- `counts[key]` = number of in-range lines for that key.
- `average_ms[key]` = total ms of in-range lines for that key divided by its
  count (a float, e.g. `5.5`, kept as integer like `5.0`).
- `malformed` = total number of malformed lines, regardless of date.
- The keys in `average_ms` and `counts` are always identical.

## Edge cases the program must handle

These are probed by the grader's hidden inputs, so the program must be correct
on all of them:

- **Both line formats** interleaved in one file.
- **Malformed lines** anywhere in the file: counted in `malformed`, otherwise
  ignored. This includes lines that look close to valid but do not match exactly
  (wrong bracket, `ms` on a `duration=` line, stray punctuation, empty lines).
- **Range boundaries**: an entry exactly on `from` or exactly on `to` counts;
  an entry one day before `from` or one day after `to` does not. The comparison
  is on the **UTC date** only (ignore time-of-day).
- **Out-of-range and error-severity entries** must simply be excluded from
  counts and averages.
- **Multiple lines sharing one key**: average over all of them (may be a
  fractional value such as `5.5`).
- **An empty log (zero lines):** `counts` and `average_ms` must both be `{}` and
  `malformed` must be `0`.

## Constraints

- The verifier runs your program **unchanged** (via `python3 /app/solve.py`) on
  hidden inputs that follow the same format, so do not hard-code to the provided
  file contents or filenames.
- No network access at verify time; standard library only.
- Do not modify `/app/operations.log` or `/app/query.txt`.