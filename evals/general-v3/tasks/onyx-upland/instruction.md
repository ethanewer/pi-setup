# Onyx Upland — reporting and export bench

The Onyx Upland analytics bench produces exact tabular artifacts from five small
data-pipeline stages. Each stage is a standalone Python 3 script in `/app` that
the verifier will run again on fresh inputs, so every script MUST be written to
take the input path and the output path as its two command-line arguments and
work correctly for ANY input file with the documented schema — never hard-code
the shipped filenames as literals beyond passing them as arguments.

The five deliverables produced by running the scripts on the shipped fixtures
are also required to exist at their `/app` paths (they are part of the submitted
state). Do NOT modify any shipped input fixture file.

All text outputs use LF (`\n`) line endings and have no trailing spaces on any
line. A line-terminated file ends with a single `\n` after its last line (i.e.
a final newline, never an extra blank line).

---

## 1. Grouped summary — `/app/aggregate.py` → `/app/summary.csv`

Shipped input: `/app/sales.csv` — CSV with header `category,amount,qty`; `amount`
and `qty` are integers (possibly negative). Blank lines may appear anywhere and
must be skipped.

Contract: `python3 /app/aggregate.py <input.csv> <output.csv>`

- Group the data rows by `category` (trim surrounding whitespace).
- Output CSV: header row exactly `category,total_amount,total_qty`, then one row
  per distinct category in ascending alphabetical order, then a final totals row
  with literal category name `TOTAL` carrying the grand totals of `amount` and
  `qty` over ALL data rows.
- Cell contents are plain integers (no decimals, no leading `+`).
- A header-only input (no data rows) yields just the header plus the `TOTAL,0,0`
  row.

## 2. Ordered result set — `/app/ordered.py` → `/app/results.csv`

Shipped input: `/app/orders.csv` — CSV with header `product_id,status,revenue,priority`.

Contract: `python3 /app/ordered.py <input.csv> <output.csv>`

- Keep only rows whose (trimmed) `status` equals `accepted` exactly (lowercase).
- Sort the kept rows by: revenue descending, then priority ascending (numeric),
  then product_id ascending (lexicographic).
- Output CSV: header `product_id,revenue,priority`, then the kept rows in that
  order. If no row is `accepted` (or the input has only a header), the output
  contains ONLY the header row. Negative revenue is allowed and sorts naturally.

## 3. Status tally — `/app/tally.py` → `/app/report.txt`

Shipped input: `/app/statuses.csv` — CSV with header `id,asset_type,status`.

Contract: `python3 /app/tally.py <input.csv> <output.txt>`

- Strip surrounding whitespace from every field. An entry counts as
  `not_found` when its trimmed `status` is exactly `not_found` (lowercase).
  `resolved = total − not_found`, where `total` is the number of data rows.
- The report has EXACTLY this layout (the two label lines each appear exactly
  once, in this order, regardless of counts):

```
=== SCAN TALLY ===
total=<N>
resolved=<N>
not_found=<N>
=== NOT-FOUND ENTRIES ===
<id of every not_found entry, in file order, one per line>
```

- When nothing is `not_found`, the `=== NOT-FOUND ENTRIES ===` label line is
  still emitted once, followed by zero id lines.

## 4. Frame range — `/app/frames.py` → `/app/frames.toml`

Shipped input: `/app/frames.conf` — a text config whose lines look like
`start=<int>` and `stop=<int>`. The two keys may appear in EITHER order; blank
lines and lines beginning with `#` must be ignored. Values may be negative.

Contract: `python3 /app/frames.py <input.conf> <output.toml>`

- Emit `/app/frames.toml` with exactly the two integer keys laid out as:

```
low = <min(start, stop)>
high = <max(start, stop)>
```

- The normalization (low ≤ high, swapping when `start` > `stop`) MUST be
  applied; equal or negative bounds are valid. The result must load with a
  standard TOML parser into exactly `{low: int, high: int}`.

## 5. Fixed-width records — `/app/fixed_width.py` → `/app/records.bin`

Shipped input: `/app/inventory.csv` — CSV with header `seq,name,code,value`.

Contract: `python3 /app/fixed_width.py <input.csv> <output.bin>`

Serialize every data row (fields trimmed) into one line with these exact widths
and alignments, then a `\n`:

| field | width | alignment   |
|-------|-------|-------------|
| seq   | 4     | right (space-padded) |
| name  | 8     | left        |
| code  | 5     | left        |
| value | 8     | right       |

- `seq` and `value` are integers formatted with no sign prefix beyond a
  leading `-` when negative, right-aligned inside their width.
- Fields are concatenated with no separator; nothing may be stripped or
  re-padded afterwards. Each record occupies exactly 25 bytes plus its `\n`.
- If a padded (or sign-extended) field would exceed its width, truncate the
  excess characters from the right of that field before writing (shipped and
  hidden inputs fit except for defensively truncable long strings).
- A header-only input produces a 0-byte output file. The entire file is
  byte-for-byte deterministic.

---

## Invocation summary

```
python3 /app/aggregate.py   <csv> <csv>     # grouped summary + TOTAL row
python3 /app/ordered.py     <csv> <csv>     # filtered + ordered result set
python3 /app/tally.py       <csv> <txt>     # label-strict status report
python3 /app/frames.py      <conf> <toml>   # normalized two-int TOML
python3 /app/fixed_width.py <csv> <bin>     # byte-exact fixed-width records
```

After writing the programs, run each one against its shipped `/app` fixture to
produce the five artifacts. The verifier re-runs every program on its shipped
fixture and on fresh hidden inputs (different categories/statuses/orderings,
header-only files, unsorted or equal frame bounds, whitespace-padded status
values, negative counts, boundary-width records) and requires the outputs to be
byte-identical to independently recomputed expected values. A single extra
space, wrong alignment, duplicated label line, CRLF that should be LF, or
off-by-one sum means the case fails.