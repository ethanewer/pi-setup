# Arid data-mart close-out

## Objective

The **Arid** group is shutting down an analytics data-mart and needs one Python
clean-up pipeline that consolidates every remaining input file into the required
close-out artifacts. You must author `/app/clean.py` — a single, self-contained
Python 3 program (stdlib + `pandas` + `numpy` are available) — that is runnable
on **any** identical-layout input directory and produces the deliverables below
by doing the transformation work itself.

The program is executed as:

```
python3 /app/clean.py <input_dir> <output_dir>
```

It must:
- create `<output_dir>` (and any subdirectories it needs),
- write every output artifact described below into `<output_dir>`,
- exit with status `0`,
- print exactly this line on stdout when everything succeeds:

```
ARID-CLOSE-OUT COMPLETE: STATUS=OK
```

## Input directory layout

Every run is given an `<input_dir>` containing these files:

| file | contents |
|------|----------|
| `metrics.csv` | columns `region,month,product_id,delivered,critical,revenue` |
| `org.csv` | columns `dept,employee,project` |
| `contacts.csv` | columns `client,account_id,month` |
| `targets.csv` | one target **variant** per line (see below) |
| `requests.csv` | columns `user,url` |
| `topk.txt` | a single non-negative integer `k` |
| `readings.csv` | columns `hour,value` (hourly time series) |
| `papers.html` | HTML with repeating paper elements |
| `recon/matrix.csv` | a numeric CSV matrix (no header) |
| `recon/rank.txt` | a single positive integer target rank `r` |

Inputs may contain rows in any order and may contain whitespace, blank lines,
and (in text/CASE) variation. Treat the table columns case-insensitively and
strip stray surrounding whitespace and quotes from header names. Never modify,
rename, or delete anything inside `<input_dir>`.

## Deliverables (written into `<output_dir>`)

### 1. `/app/summaries.csv` — grouped aggregation with boolean-column detection
From `metrics.csv`, detect the two boolean columns (`delivered`, `critical`) by
recognising truthy/falsy spellings — any of `1 / 0`, `Yes / No`,
`TRUE / FALSE`, `True / False`, `true / false` (case-insensitive). Group rows by
`(region, month)` and compute:

- `delivered_count` — number of truthy `delivered` rows,
- `critical_count` — number of truthy `critical` rows,
- `revenue_total` — sum of `revenue`, rounded to 2 decimals,
- `revenue_avg` — mean of `revenue`, rounded to 2 decimals.

Header: `region,month,delivered_count,critical_count,revenue_total,revenue_avg`.
Rows sorted by `region` ascending, then `month` ascending. A group with a single
row is still emitted. Boolean columns must be treated as booleans (not strings)
so the counts are numeric.

### 2. `/app/category_lists.csv` — result groupable by category
Group the same `metrics.csv` by `region` and collapse each region's distinct
`product_id` values into a `;`-separated list. Columns `category,product_ids`
(`category` = region). Within each list, sort product ids ascending and dedupe.
Rows sorted by `category` ascending. This table must keep a category label and
product identifiers so a downstream `groupby(region)` collapses to per-category
lists.

### 3. `/app/result.json` — nested `departments -> employees -> projects` graph
From `org.csv` (columns `dept,employee,project`), build a nested object:

```json
{
  "departments": [
    { "name": "<dept>", "employees": [
        { "name": "<employee>", "projects": ["<p1>", "<p2>"] }
    ] }
  ]
}
```

- one department entry per distinct `dept`, one employee entry per distinct
  `(dept, employee)`, projects are the distinct project names for that employee,
- departments sorted ascending by name, employees sorted ascending by name,
  projects sorted ascending,
- no duplicate projects for a given employee, no duplicate employees or
  departments.

### 4. `/app/contacts_filtered.csv` — target entity across name/identifier variants
Filter `contacts.csv` down to the **target entity**, matching any record whose
`client` OR `account_id` equals any variant listed in `targets.csv`. Matching is
case-insensitive and trims surrounding whitespace (blank lines in `targets.csv`
are ignored). Keep all original columns, drop duplicate rows, and sort by
`client` ascending then `account_id` ascending. Only target records are emitted.

### 5. `/app/top.tsv` — top-k request URLs ranked by frequency
From `requests.csv`, count how many times each `url` occurs across all rows
(trim surrounding whitespace from each url before counting). Rank by frequency
descending; break ties by url ascending. Take the top `k` (from `topk.txt`,
which may have surrounding whitespace). Write a header line `url<TAB>count`
followed by `k` data lines `url<TAB>count` (count is the integer frequency).

### 6. `/app/hourly.csv` — fill gaps in an hourly series
`readings.csv` is an hourly series where some hours are missing entirely and/or
have an empty `value`. Sort by `hour`. The expected series spans, at hourly
resolution, from the earliest hour (floor of the earliest timestamp) to the
latest hour inclusive. Produce every hour in that span, one row per hour,
columns `hour,value` with `hour` formatted `YYYY-MM-DDTHH:MM:00`. Fill:

- hours missing between two known values → **linear interpolation**,
- a missing value at a boundary (an empty/leading/trailing hour) → **fallback to
  the nearest known value** (borrow forward for a leading hole, backward for a
  trailing hole).

No row may be left with a NaN/empty value. Round values to 6 decimals.

### 7. `/app/papers.jsonl` — JSON Lines, exactly two fields per paper
`papers.html` contains repeating paper elements:

```html
<div class="paper">
  <span class="paper-id">P-101</span>
  <a class="paper-link" href="/papers/P-101">Vapor</a>
</div>
```

Emit one JSON object **per paper element** on its own line in
`papers.jsonl`. Each object has **exactly two** keys: `"id"` (a string, the text
inside `<span class="paper-id">`) and `"url"` (a string, the `href` attribute of
`<a class="paper-link">`). If a paper element lacks an `<a class="paper-link">`,
its `url` is the empty string `""`. Every paper element must yield a record; no
record for any other element. The class selectors may appear with extra tokens
(e.g. `class="paper paper-x"`) and the HTML may contain arbitrary whitespace.

### 8. `/app/trials/trial_00.csv` … `/app/trials/trial_19.csv` — 20 low-rank reconstructions (trial-indexed CSV artifacts)
Read the numeric matrix from `recon/matrix.csv` (no header) and target rank `r`
from `recon/rank.txt`. Perform a rank-`r` truncated-SVD reconstruction of the
matrix (keep the `min(r, rows)` largest singular components). Repeat this
reconstruction across **20 trials** and persist each resulting table as a
comma-separated CSV named by its trial index:

- `trial_00.csv`, `trial_01.csv`, …, `trial_19.csv`
  (zero-padded to two digits) inside a `trials/` sub-directory of
  `<output_dir>`.

Each file must be comma-separated and equal the rank-`r` reconstruction (an
input that is itself full-rank, with `r` smaller than its rank, must be reduced
to exactly rank `r`). The 20 files are produced by repeating the recovery
process per trial index. Any reasonable numeric formatting is acceptable.

## What you must deliver

1. `/app/clean.py` — the program described above.
2. Run it against the provided sample input so the deliverables land in `/app`:

```
python3 /app/clean.py /app/input /app
```

This must leave `/app/result.json` and `/app/top.tsv` (and the other artifacts)
present under `/app`. Do not delete `/app/input`; it is needed again later.

Your `/app/clean.py` will be re-run on **hidden** input directories that follow
the same layout but with different data, including edge cases: empty/leading and
trailing boundary readings, boolean strings written as `1/0` or `TRUE/FALSE`,
whitespace and case variation in client/target names and urls, `topk.txt`
whitespace, papers missing a link, duplicate org rows, single-row metric groups,
and full-rank matrices reconstructed to a lower rank. Handle these generally.

## Success criteria

The pipeline must run on any such input directory, exit `0`, print the completion
line, and produce every artifact in the exact formats above. The verifier
re-runs `/app/clean.py` on the hidden directories and independently checks all
eight deliverables.
