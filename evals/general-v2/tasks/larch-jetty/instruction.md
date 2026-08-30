# Meridian back-office consolidator

You are consolidating five slices of a regional payment office's operational data
in an offline environment. A directory at **`/app/data`** contains the live
fixtures. You must produce a **single reusable program** `/app/solve.py` plus
its output `/app/answer.json`.

## Deliverables

1. `/app/solve.py` — a program you write, runnable from anywhere, that:

   ```
   python3 /app/solve.py [<input_dir>] [<output_json>]
   ```
   - Defaults: `input_dir=/app/data`, `output_json=/app/answer.json`.
   - When given explicit arguments it must run identically on any other data
     directory and write to the second argument instead.
   - It **must not** hardcode any values from the visible fixtures. It will be
     re-run on hidden datasets with different files, so it must be fully driven
     by what it reads.

2. `/app/answer.json` — JSON produced by running `solve.py` on `/app/data`.
   The exact schema is fixed (see "Output schema").

Do not modify anything under `/app/data`. Do not touch `/tests`.

## Input layout (applies to `/app/data` and every hidden dataset)

```
<dir>/
  transactions.csv      # comma-separated, one header line, then data rows
  calendars/<name>.ics  # zero or more iCalendar files (blocking schedules)
  candidate.txt         # availability probes (see below)
  logbook.txt           # one line per log entry
```

### transactions.csv
Header line: `date,description,amount,account,category,product_id`.
Every data row has exactly these six fields, in that order.
- Fields may be quoted; `description` a.o. may contain commas; `amount` fields
  carry thousands separators and are quoted for that reason.
- Amounts are **currency strings**: may include `$ `£ `€`, `+`/`-` sign, thousands
  separators, and decimals, e.g. `-$1,250.00`, `+€610.00`, `£40.30`, `12.5`.
- The same logical vendor frequently appears with **spelling variants** of
  `description` and **account-number variants** in `account`.
- A fully blank data row (every field empty) is ignored; otherwise every data
  row is preserved.

### calendars/*.ics
iCalendar files. `VEVENT` blocks carry `SUMMARY`, `DTSTART`, `DTEND` using UTC
timestamp tokens of the form `YYYYMMDDTHHMMSSZ` (e.g. `20260610T090000Z`).
A VEVENT is a **blocking interval** only if it has **both** a `DTSTART` and a
`DTEND`; a VEVENT missing either is **dropped** (never a block). Summary may be
empty. Blocks are treated as half-open `[start, end)`.

### logbook.txt
One entry per line. A line may contain zero or more dotted-quad candidates and
zero or more ISO dates `YYYY-MM-DD`. A candidate counts as a **valid IPv4** only
if it is exactly four octets separated by dots, each octet is an integer in
`0..255`, and no octet has a leading zero (so `10.0.0.1` and `255.255.255.255`
are valid; `999.1.1.1`, `256.0.0.1`, `012.1.1.1`, and IPv6 forms like
`2001:db8::1` are **not**).

## Output schema (exactly these keys)

```json
{
  "csv_rows": [ {"date": ".", "description": ".", "amount": ".", "account": ".", "category": ".", "product_id": "."}, ... ],
  "top_categories": ["<cat>", ...],
  "by_category": { "<category>": ["<product_id>", ...], ... },
  "calendar_blocks": { "<file_basename>": [ {"summary": "...", "start": "TOKEN", "end": "TOKEN"}, ... ], ... },
  "availability": [ {"file": "...", "label": "...", "start": "TOKEN", "end": "TOKEN", "available": true|false }, ... ],
  "ip_dates": [ {"ip": "...", "date": "YYYY-MM-DD"}, ... ]
}
```

Detailed rules:

- **`csv_rows`** — every preserved data row (file order) as a dict keyed by the
  header names. Every value must be the **exact original characters** from the
  file: spelling is not normalized, `account` variants are not rewritten, and
  `amount` keeps its original sign and currency and thousands separators.
  (Parsing the amount numerically is only needed for ranking — you still emit
  the raw string here.)

- **`top_categories`** — for each `category`, first convert `amount` to a
  number: a leading `-` makes it negative, otherwise positive; strip everything
  that is not a digit or `.`; a string with no digits parses to `0.0`. Sum the
  **absolute value** of every row's amount **per category**. Order categories by
  that total **descending**; ties broken **alphabetically by category name**
  (ascending). Keep exactly the **first 5**. If there are fewer than 5
  categories keep all.

- **`by_category`** — for each category, the sorted, de-duplicated list of its
  `product_id` values. Categories listed in alphabetical order.

- **`calendar_blocks`** — keyed by ICS **file basename**, the parsed blocking
  intervals (with both DTSTART and DTEND) as `{summary, start, end}` where
  `start`/`end` are the raw `YYYYMMDDTHHMMSSZ` token strings.

- **`availability`** — read `candidate.txt`. Each line:
  `file=<basename>;label=<text>;start=<token>;end=<token>` (fields `;`-separated,
  key=value). `available` is **true** unless the probe window `[start,end)`
  overlaps any blocking interval in that `file`'s calendar. Overlap uses
  half-open semantics: windows that only touch a block's edge (probe start ==
  block end, or probe end == block start) do **not** overlap. A probe for a
  calendar file that does not exist (or has no blocks) is fully available.
  Order of probes is preserved.

- **`ip_dates`** — for every line in `logbook.txt`, if the line contains **at
  least one valid IPv4**, emit one entry: `ip` = the **first** valid IPv4 on the
  line, `date` = the **rightmost** ISO `YYYY-MM-DD` date on that line (the last
  `findall` match). Lines with no valid IPv4 are skipped; a line with a valid
  IPv4 but no date is skipped.

Everything must be derived from the input; no hardcoded facts.

## What the grader will do (for confidence)
In `/app` I will run `solve.py` on the visible `/app/data` and on hidden
datasets, then re-derive the expected output from the same rules and compare
every field (including field order for lists). Any mismatch → zero reward. Make
the program read every input and be correct on all documented edges (amounts
that parse to 0, ties at rule boundaries, invalid IPs, missing DTEND, exact
boundary overlaps).

Write `/app/solve.py` using any standard-library approach (csv, re, json,
datetime). You are allowed to use the pandas and python-dateutil packages
installed in the image if you prefer.