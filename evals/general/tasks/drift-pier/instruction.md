# Drift Pier data-mart close-out

A harbourside data mart finishes its nightly close-out with a single Python
pipeline. Write **`/app/clean.py`**, a self-contained program that reads a job
input directory and writes every required output to an output directory.

The deliverable program is executed as:

```
python3 /app/clean.py <input_dir> <output_dir>
```

- `<input_dir>` holds a set of source files (always produced by the same job
  layout described below; every `input_dir` you run against has **exactly this
  layout and file name set**).
- `<output_dir>` may be empty or missing; the program must create it and write
  the three required outputs there.
- The shipped image provides a populated source directory at `/app/data`. You
  must produce the deliverables **`/app/result.json`** and **`/app/top.tsv`** at
  the top level of `/app` (run e.g. `python3 /app/clean.py /app/data /app`), and
  the program must also work on brand-new input directories with the same layout.

The program must be correct for **any** input set following the layout,
including the edge cases enumerated below. It must not depend on the specific
marching numbers in `/app/data`.

## Source files in `<input_dir>`

### 1. `ledger.json` (transfer rule)
JSON with two keys:
- `parties`: object mapping a party id -> `{"name": ..., "balance": <float>}`.
- `assets`: array of objects each `{"id": ..., "name": ..., "owner": <party
  id>, "price": <float>}`.

`owner` is the id of the party that currently possesses the asset.

### 2. `transfers.csv` (proposed transfers)
CSV with header `order,buyer,seller,asset`. One proposed transfer per row;
rows are processed **in file order**. Fields may carry surrounding whitespace
(trim them).

Validation + transfer rule, applied row by row against the current state:
1. If `buyer` **or** `seller` is not a known party, reject with reason
   `unknown parties`.
2. Else if `buyer == seller`, reject with reason `same party`.
3. Else if `asset` is not a known asset id, reject with reason `unknown asset`.
4. Else if the asset's **current owner** is not `seller`, reject with reason
   `asset not owned by seller`.
5. Otherwise approve: **debit the buyer** (buyer balance `-= asset.price`),
   **credit the seller** (seller balance `+= asset.price`), **reassign** the
   asset's owner to `buyer`, and append an `approved` log entry.

Order matters: an asset rejected in an early row can become valid later only if
a prior approved row changed its owner to match the new seller.

The default `/app/data` ledger demonstrates approved, changed-owner rejections,
party-missing rejections, and an asset-reassignment chain: `hull/keel/gunw`
trade `dock-winch`, `sea-bollard` and `life-ring`, and the intermediate rows
should make the running balances end at `hull=238`, `keel=87`, `gunw=15` with
`sea-bollard -> gunw`, `dock-winch -> keel`, `life-ring -> gunw`.

### 3. `metrics.csv` (grouped aggregation + boolean detection)
Comma CSV. The **first column is the grouping key** (a string). Every other
column is either a **numeric** column (real-valued data) or a **boolean**
column (logical flags). A column is boolean when every non-empty cell parses
as `true|1|yes|t` or `false|0|no|f` (lowercased, trimmed). Numeric columns are
the remaining non-key columns; their cells parse as floats.

Per group (sorted by group key, group key trimmed; rows with an empty group key
are skipped) report:
- `n`: number of rows in the group;
- for each numeric column `c`: `c_sum` and `c_mean` (mean = sum / n, rounded to
  6 decimals; dict keys literally `load_sum`, `load_mean`, `slots_sum`, ...);
- for each boolean column `c`: `c_true` = count of truthy cells.

### 4. `tide.csv` (interpolation) 
CSV columns `port,hour,record`. `record` may be empty (a gap) or a float. Rows
are grouped per `port`; within a port the rows are ordered ascending by `hour`
(ties keep file order). Fill every empty `record`:
- if there are known values both **before and after** the gap, linearly
  interpolate along `hour`: `v_before + (v_after - v_before) * (h - h_before) /
  (h_after - h_before)` (if the two hours are equal, use the before value);
- if only a **later** value exists (leading gap), clamp to the first available
  value;
- if only an **earlier** value exists (trailing gap), clamp to the last
  available value;
- if a port has **no** known value at all, leave every row of that port empty.

Write the completed table as `tide_filled.csv`: same rows in the original file
order, with every filled `record` emitted as a number (whole numbers as e.g.
`7`, non-integer to at least 6 decimals). Empty cells stay empty.

### 5. `surge.tsv` (request log for top-k ranking)
Tab-separated (a real tab character). It has a header row and a column literally
named `url`. Count how many rows carry each `url` (empty url cell -> skip; trim
the value). Rank distinct urls by **count descending**, ties broken by **url
ascending**, and write the **top 3** (if fewer than 3 distinct urls, write all
of them).

### 6. `schedule/*.ics` (iCalendar blocking intervals)
Every file named `*.ics` under `schedule/`. Inside each, every `VEVENT` block
carries a `DTSTART:<YYYYMMDDTHHMMSS>Z` and a `DTEND:<YYYYMMDDTHHMMSS>Z` line
(optionally without the trailing `Z`). Convert each to ISO
`YYYY-MM-DDTHH:MM:SS`. A pair `{start,end}` is added to that file's list only if
both lines are present; **de- duplicate** identical repeat pairs (an event
included twice yields a single entry). A `VEVENT` missing its `DTEND`, or a
`DTEND` with no preceding `DTSTART`, yields nothing. Garbage lines are ignored.

## Outputs written to `<output_dir>`

### `result.json` — a single JSON object with these keys:
- `"boolean_columns"`: array of detected boolean column names (from #3),
- `"by_group"`: object mapping each group key -> its aggregate object (from #3),
- `"balances"`: object mapping **every** party id -> final balance (#2), 
- `"ownership"`: object mapping **every** asset id -> its current owner (#2),
- `"transfer_log"`: array preserving row order; each entry
  `{"order": ..., "asset": ..., "buyer": ..., "seller": ..., "status":
  "approved|rejected", "reason": <null|reason>, "price": <number|null>}`
  with the fields of #2,
- `"slots"`: object mapping each `*.ics` filename (basename) -> array of
  `[start,end]` interval pairs (#4).

### `top.tsv` — the top-k ranked urls
`<url><TAB><count>` one per line (no header), in the ranking order of #5.

### `tide_filled.csv` — the filled tide table from #4.

`result.json`, `top.tsv` and `tide_filled.csv` are produced under
`<output_dir>`. The default `/app` run must also produce the deliverable copy of
`result.json` and `top.tsv` at the top of `/app`.

## Deliverables
- `/app/clean.py` — the pipeline program (must be runnable on any `input_dir`).
- `/app/result.json` — populated by the default `/app/data` run.
- `/app/top.tsv` — populated by the default `/app/data` run.

## Edge cases you must handle
These are exercised by the hidden grading inputs:
- boolean columns written as `1/0` **or** as `true/false` words; numeric columns
  whose integer values would be mistaken for booleans if not for a cell like `2`.
- transfer orders that reference unknown parties, unknown assets, a `buyer ==
  seller`, and an asset not owned by the seller; a chain where a previously
  rejected asset becomes valid after a later row changes its owner; row ordering
  of the resulting log.
- tide ports that mix truly interior gaps with leading-only and trailing-only
  gaps, a fully-empty port, and repeated hours inside a port.
- a top-k with a tie straddling the top-3 cutoff, and inputs with fewer than 3
  distinct urls.
- `.ics` files with duplicate intervals, a `VEVENT` missing its `DTEND`, and
  garbage / malformed lines.

Do not modify `/app/data`'s fixtures in a way that breaks the shipped baseline;
the harness re-supplies them.