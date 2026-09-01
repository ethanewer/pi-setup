# Contact-Directory Conflict Report

You maintain the unified contact directory for **Cedarline Outfitters**. The same
person records live in three upstream systems (`crm`, `billing`, `support`) and
the rows disagree. You must build a reusable merge tool that produces an exact
conflict report. The verifier recomputes the report from scratch on its own
hidden inputs, so your tool must implement the rules below on **any** conforming
input, not just the provided fixture.

## Environment

- Working directory: `/app`. It already contains the input file
  `/app/contacts.csv`. Python 3.12 is available as `python3`.
- **Do not modify `/app/contacts.csv`.**

## Deliverables (both required)

1. `/app/merge_contacts.py` — a runnable Python program with this interface:
   ```
   python3 /app/merge_contacts.py <input_csv> <output_json>
   ```
   It reads the CSV and writes the JSON conflict report to the given output
   path. It must work on any input conforming to the contract below.

2. `/app/merge_report.json` — the report your program produces **when run on
   the provided `/app/contacts.csv`**:
   ```
   python3 /app/merge_contacts.py /app/contacts.csv /app/merge_report.json
   ```

## Input format

`/app/contacts.csv` (and every hidden input) is a comma-separated text file.
The **first line is a header and is skipped**. Every subsequent line should
describe one record as:

```
user,field,source,value
```

Rules for interpreting data lines:

- Split each line on `,` and **strip surrounding whitespace from every field**.
- A line is usable only when it yields **exactly four non-empty fields** and its
  `source` is one of the literal tokens `crm`, `billing`, `support`.
- **Blank lines are ignored entirely** (they are not errors and are not counted).
- Any other non-blank line (wrong column count, empty field after trimming,
  unknown source token) is **skipped and counted** in the report's `skipped` total.
- If the same `(user, field, source)` triple appears several times, the
  **last occurrence wins** (earlier duplicates are overwritten).

Source priority is fixed: **`crm` > `billing` > `support`**.

## Conflict semantics

For each `(user, field)` pair, collect the values of all sources present for it.

- A **conflict** occurs when **at least two distinct values** exist among the
  present sources for that pair.
- The **winner** is the value of the highest-priority source present
  (`crm`, then `billing`, then `support`).
- Pairs with a single source, or where all present sources agree on the value,
  are **not** conflicts and never appear in the report.

## Required output JSON

The output file must be valid JSON with exactly these keys:

```json
{
  "total_conflicts": <int>,
  "skipped": <int>,
  "users": [
    {
      "user": "<user>",
      "conflicts": [
        {
          "field": "<field>",
          "sources": [
            {"source": "<source name>", "value": "<value>"}
          ],
          "winner": "<chosen value>"
        }
      ]
    }
  ]
}
```

- `users` lists **only users that have at least one conflict**, sorted
  ascending by the `user` string (standard Python string sort).
- Within a user, `conflicts` is sorted ascending by `field` (standard string
  sort).
- `sources` lists the present sources in **priority order** (`crm` first, then
  `billing`, then `support`), each as `{"source": ..., "value": ...}` with the
  value that source holds after duplicate resolution.
- `winner` is the chosen value per the priority rule above.
- `total_conflicts` must equal **exactly** the total number of conflict entries
  across all users (`sum(len(u["conflicts"]) for u in users)`).
- `skipped` is the number of skipped non-blank data lines (see above).

## Edge cases the grader probes (hidden inputs)

- Three sources present for one pair with three different values.
- Duplicate rows for the same `(user, field, source)` — the last one decides
  both the stored value and whether a conflict exists.
- Pairs where every source agrees (no conflict), and single-source pairs.
- Rows with wrong column counts, empty fields, or unknown source tokens
  (counted in `skipped`), plus blank lines (ignored).
- An input with only the header line (plus blank lines): all counts `0` and
  `"users": []`.

## Constraints

- The verifier runs your program **unchanged** (`python3 /app/merge_contacts.py`)
  on hidden inputs that follow the same format, so do not hard-code to the
  provided file's contents or filename.
- No network access at verify time; standard library only.
- Do not modify `/app/contacts.csv`.
