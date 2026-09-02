# OnyxSpire — manifest locale export

The freight desk of Onyx Spire keeps its container manifests as one large
newline-delimited JSON dump. You must build a reusable export tool that pulls
out a single locale subset and writes the requested columns as JSON Lines.
The tool must work **on any input** that follows the documented format below,
not just on the provided files — the grader re-runs your program on hidden
inputs.

## Environment

- Working directory: `/app`. It already contains the input files
  `/app/manifest.jsonl` and `/app/job.txt`. Python 3.12 is available as
  `python3`.
- **Do not modify `/app/manifest.jsonl` or `/app/job.txt`.**

## Input formats

`manifest.jsonl` — one JSON value per line. Most lines are JSON **objects**
that may carry any of these fields (others may exist too, and some fields may
be absent on some rows):

```json
{"waybill": 700001, "port": "Rotterdam", "locale": "de-DE",
 "weight_kg": 12340.5, "carrier": "Nordwind", "sealed": true, "notes": "..."}
```

A line may also be **blank**, **malformed JSON**, or a valid JSON value that is
**not an object** (e.g. a number, string, or array). Those lines are skipped
silently — the program must never crash on them.

`job.txt` — plain text, `key=value` lines (one `locale` line and one `columns`
line):

```
locale=de-DE
columns=waybill,port,weight_kg
```

- `locale` is the exact locale string to keep (exact string match against the
  row's `"locale"` field).
- `columns` is a comma-separated list of column names to export, **in the
  order requested** (the order in the output must follow the requested order,
  not the order in the row).

## Deliverables (both required)

1. `/app/export_rows.py` — a runnable Python program with this interface:
   ```
   python3 /app/export_rows.py <dataset_jsonl> <job_file> <output_jsonl>
   ```
   It reads the dataset and the job spec and writes the filtered rows to the
   output path as newline-delimited JSON.

2. `/app/answer.jsonl` — the export your program produces **when run on the
   provided `/app/manifest.jsonl` and `/app/job.txt`**:
   ```
   python3 /app/export_rows.py /app/manifest.jsonl /app/job.txt /app/answer.jsonl
   ```

## Exact filtering / emission rules

- Keep only rows that are JSON objects whose `"locale"` field **exists and
  equals** the requested locale (exact string equality). A row whose `locale`
  field is absent is dropped (never an error).
- For each kept row, emit one JSON object whose keys are **exactly** the
  requested columns, in the requested order. A requested column that a row
  does not carry is emitted as JSON `null` (never an error, never a crash).
  Present columns pass their value through **unchanged** (numbers stay
  numbers, strings stay strings, `true`/`false` stay booleans, nested objects
  stay objects).
- Output is one JSON object per line, no header, UTF-8. Zero kept rows means
  a **zero-byte (empty)** output file.
- Blank lines, malformed JSON lines, and non-object JSON lines in the dataset
  are skipped silently.
- The program must not require any third-party libraries (standard library
  only) and must not hard-code the provided file contents.

## Edge cases the grader probes

- Datasets with several locales interleaved; only the requested subset is kept.
- Rows missing the requested column → `null` in the output for that column.
- Rows missing the `locale` field → dropped.
- Malformed / blank / non-object lines anywhere → skipped, never a crash.
- A job whose locale matches **no** rows → empty output file.
- Unicode text in field values must survive the round trip exactly.
- Column order in every output object must match the `columns=` request order.

## Constraints

- No network access at verify time; standard library only.
- The verifier runs your program **unchanged** on hidden inputs that follow
  the same formats, so nothing may be hard-coded to the provided fixtures.
- Do not modify `/app/manifest.jsonl` or `/app/job.txt`.
