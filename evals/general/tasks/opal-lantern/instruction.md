# Export a locale subset of the ornithology survey archive

The Meridian Ornithology Cooperative stores its field-survey archive as a
newline-delimited JSON dataset in `/app/survey.jsonl`. You must build a
reusable command-line exporter that keeps only the records of one locale and
writes the requested columns to a JSONL file. The exporter must work **on any
input** that follows the documented format below, not just on the provided
file.

## Environment

- Working directory: `/app`. It already contains the input file
  `/app/survey.jsonl`. Python 3.12 is available as `python3` (standard
  library only; no network).
- **Do not modify `/app/survey.jsonl`.**

## Deliverables (both required)

1. `/app/export_locale.py` — a runnable Python program with this interface:
   ```
   python3 /app/export_locale.py --input FILE --locale LC --columns SPEC --output OUT
   ```
   It reads a JSONL dataset, filters to one locale, and writes the selected
   columns to `OUT` as newline-delimited JSON. It must work on any dataset
   conforming to the contract below.

2. `/app/exports/survey_fr.jsonl` — the export your program produces **when
   run on the provided `/app/survey.jsonl`** with:
   ```
   python3 /app/export_locale.py --input /app/survey.jsonl --locale fr-FR \
     --columns record_id,meta.site,meta.banding.ring,species,count --output /app/exports/survey_fr.jsonl
   ```

## Input format

`--input FILE` is UTF-8 newline-delimited JSON. Each line is in exactly one of
three categories:

- **Record:** a line that parses as a JSON **object**. Records carry a
  `"locale"` string field (e.g. `"en-US"`, `"fr-FR"`, `"ja-JP"`, `"pt-BR"`)
  and arbitrary other fields, which may nest (objects inside objects).
- **Malformed line:** a line that fails to parse as JSON or parses to a JSON
  value that is **not an object** (e.g. an array or a bare number).
- **Blank line:** a line that is empty or whitespace-only.

Malformed and blank lines are skipped silently (never an error).

## Filtering and column selection

- Keep exactly the records whose `"locale"` field **equals** `LC` (exact
  string match). A record with an absent `locale` field is dropped.
- `SPEC` is a comma-separated list of **column selectors**. Each selector is
  either a plain key (`record_id`) or a **dotted path** into nested objects
  (`meta.site` means `record["meta"]["site"]`; paths may be deeper).
- For each kept record, emit one JSON object whose keys are exactly the
  requested selectors, **in the requested order**. A selector whose path does
  not resolve on a record (missing intermediate key, or the intermediate value
  is not an object) is emitted as the empty string `""` — never an error.
- Kept records are emitted in **input order** (no sorting).
- Write one JSON object per line with `ensure_ascii=False` and no trailing
  newline after the final record beyond the usual line terminator. If zero
  records match, `OUT` is an **empty file**.
- `OUT`'s parent directory may not exist; the program must create it.

## Required output

`OUT` contains one line per kept record, e.g.:

```json
{"record_id": "S-0142", "meta.site": "Camargue", "meta.banding.ring": "FR-88231", "species": "Sterna hirundo", "count": 3}
```

(The exact whitespace of each line does not matter; the verifier compares the
parsed JSON objects.)

## Edge cases probed by hidden inputs

The verifier re-runs your program unchanged on hidden datasets, so it must
handle all of the following correctly:

- a **different locale** than the visible one, and **different column
  selectors** (different depth, different order);
- **zero matching records** → empty output file;
- records **missing** some requested keys or intermediate nesting;
- **malformed lines** (broken JSON, JSON arrays, bare scalars) and **blank
  lines** interleaved with records — skipped, never crashing;
- **Unicode** values that must be preserved exactly (not `\uXXXX`-escaped or
  mangled);
- an **empty input file** (zero lines).

## Constraints

- Do not hard-code the provided file contents or locale.
- No network access; Python standard library only.
- Do not modify `/app/survey.jsonl`.