# SaffronLoom — locale-filtered catalog export

The localization team of **SaffronLoom Studios** ships UI string catalogs as
one big JSON dump. You must build a reusable command-line exporter that pulls
a single locale out of such a dump and writes exactly the requested columns as
newline-delimited JSON. The program must work **on any input** conforming to
the contract below, not just on the provided files.

## Environment

- Working directory: `/app`. It already contains the input files
  `/app/catalog.json` and `/app/task.json`. Python 3.12 is available as
  `python3` (standard library only; no network access).
- **Do not modify `/app/catalog.json` or `/app/task.json`.**

## Deliverables (both required)

1. `/app/export_lang.py` — a runnable Python program with this interface:
   ```
   python3 /app/export_lang.py --input FILE --query QUERY --output OUT
   ```
2. `/app/fr_export.jsonl` — the export your program produces **when run on the
   provided `/app/catalog.json` with the query in `/app/task.json`**:
   ```
   python3 /app/export_lang.py --input /app/catalog.json --query /app/task.json --output /app/fr_export.jsonl
   ```

## Input formats

**Dataset file (`--input`):** one JSON document in one of two shapes:

- a JSON **array** of row objects, or
- a JSON **object** with a `"records"` key holding the array of row objects
  (any other top-level keys, e.g. `"meta"`, must be ignored).

Each row is a JSON object with arbitrary fields. Rows in the dump may or may
not carry a `"locale"` field; row order in the file defines the output order.

**Query file (`--query`):** a JSON object:

```json
{"locale": "fr", "columns": ["id", "target", "plural"]}
```

## Required behaviour of `/app/export_lang.py`

- Read the dataset and keep exactly the rows whose `"locale"` field **equals**
  the queried locale (exact string match — `"FR"` never matches `"fr"`).
- A row whose `locale` field is **absent** (or not a string) is dropped, and
  must never cause an error.
- For each kept row, in the **original dataset order** (no sorting), emit one
  JSON object whose keys are **exactly the requested `columns`, in the order
  requested**. A requested column that a row does not carry is emitted as the
  empty string `""` — never `null`, never an error, never a crash.
- Write the result to `OUT` as newline-delimited JSON: one compact JSON object
  per line, no header, and an **empty file (zero rows; a zero-byte file is
  fine) if no row matches**.
- Do not emit any keys that were not requested, and never reorder or dedupe
  rows: duplicate rows in the input produce duplicate output lines.

## Edge cases the grader probes (hidden inputs follow the same contract)

- Both dataset shapes (bare array and `{"records": [...]}` wrapper).
- Rows with a **missing or non-string `locale`** are dropped silently.
- A row with a **wrong-case locale** (`"DE"`) is not a match for `"de"`.
- A requested column that **some or no kept rows carry** → `""` for those rows.
- An **empty dataset** (zero records) → an empty output file.
- A locale that **matches zero rows** → an empty output file.
- The exact **row count** and **column names/order** are asserted by the
  grader on every case.

## Constraints

- The verifier runs your program **unchanged** (via
  `python3 /app/export_lang.py`) on hidden inputs, so do not hard-code the
  provided file contents or filenames.
- Standard library only; no network at verify time.
- Do not modify `/app/catalog.json` or `/app/task.json`.
