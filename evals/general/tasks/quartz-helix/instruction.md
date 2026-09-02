# quartz-helix: data-mart close-out tool

You are handed a fresh Python 3.12 container (with `pandas` and `numpy`
installed) that holds a set of CSV/TSV workbench fixtures under **`/app/data`**.
There is no existing project — everything is yours to author. Your job is to
build one deterministic, reusable transformation tool at **`/app/clean.py`**
and run it against the shipped data to produce the two data deliverables.

Working deliverables (the only artifacts the verifier touches):

1. **`/app/clean.py`** — a single Python script (make it executable) exposing
   several subcommands (below). It must run offline and be re-runnable, without
   crashing, on *any* input files that follow the same schema as the shipped
   fixtures. The verifier re-invokes it on fresh/hidden inputs, so behaviour
   must come from the input data, never from hard-coded answers.
2. **`/app/result.json`** — the nested organisation graph, produced by running
   the `organize` subcommand on the shipped `/app/data` org CSVs.
3. **`/app/top.tsv`** — the top-5 request URLs by frequency, produced by running
   the `topk` subcommand on `/app/data/requests.csv`.

---

## Shipped data (`/app/data`, same schema as hidden inputs)

* `departments.csv` — columns `dept_id,dept_name`
* `employees.csv`   — columns `emp_id,dept_id,emp_name`
* `projects.csv`    — columns `proj_id,dept_id,proj_name`
* `requests.csv`    — columns `ts,url,user_agent` (a `url` may repeat; it may contain query strings, e.g. `/search?q=a`)
* sample self-check fixtures: `sample_sales.csv`, `sample_invoices.tsv`,
  `sample_hourly.tsv`, `sample_filter.csv`, `sample_target.csv`,
  `sample_papers.csv` (use these locally to validate each subcommand).

## Tool contract (`/app/clean.py`)

Implement exactly these subcommands. Where a delimiter is not listed the
default is comma; `totals` and `series` default to TAB.

### `organize DEPT EMP PROJ [-o OUT]`
Reads the three CSVs and writes a JSON object with **exactly this shape**:

```json
{
  "organization": {
    "<dept_id>": {
      "name": "<dept_name>",
      "employees": ["<emp_name>", ...],
      "projects": ["<proj_name>", ...]
    }
  }
}
```

* Keys are the `dept_id`s from `DEPARTMENTS.csv`, sorted alphabetically.
* Every department in `departments.csv` appears, even one with zero employees
  (or zero projects) — those arrays are simply empty.
* Each `employees`/`projects` array holds only the distinct names whose row
  points at that department (`dept_id` matches), **sorted alphabetically, with
  no duplicates** (a duplicated name counts once).
* Rows whose `dept_id` is not present in `departments.csv` (orphans) are dropped.
* Output is written to `OUT` (default `/app/result.json`).

### `filter RECORDS TARGET [-o OUT] [--delim ,]`
`RECORDS` has columns `name,account_id,amount,region` (or a 4-column variant);
`TARGET` has columns `display_name,account_id` and holds **one or more alias
rows that all describe the same target entity**. A record belongs to the target
if its `name` (compared **case-insensitively, whitespace-trimmed**) equals any
`display_name` in `TARGET`, **or** its `account_id` (trimmed) equals any
`account_id` in `TARGET`. Write **all and only** the matching records, in their
original order, with the original schema. Rows that match on neither are
excluded; do not match partial/approximate identifiers.

### `topk ACCESS [-k N] [-o OUT] [--delim ,]`
`ACCESS` has a `url` column. Count how many times each distinct, non-empty
`url` appears, then print the top `N` (default 5) as lines
`URL<TAB>count`, ordered by **descending count**, ties broken by **ascending
URL** (lexicographic). If fewer than `N` distinct urls exist, print all of them.

### `grouped IN --category COL --vars V1 [V2 ...] [-o OUT] [--delim ,]`
Group the rows by the values of `COL`. For each group, emit one CSV row:
`COL, nrows, V1_agg, V2_agg, ...` where `nrows` is the number of rows in the
group. For each variable column, first **detect** whether it is boolean:
a column is *boolean-detected* when it has at least one non-empty cell and every
non-empty cell (compared lower-cased, trimmed) is a token in
`0,1,yes,no,true,false,y,n,t,f`. A boolean-detected column's aggregate is the
**fraction (0..1) of its non-empty cells that are true-ish** (`1,true,yes,y,t`),
emitted as a column named `V_true_frac`. Any other column is treated as numeric
and its aggregate is the **mean over its non-empty numeric cells**, emitted as
`V_mean` (empty cells are excluded from the mean). Rows are grouped by the
trimmed category value; output rows are sorted by that category key. If a
group's aggregate denominator is zero the cell is left empty.

### `totals INVOICES [-o OUT] [--delim TAB]`
`INVOICES` is a TAB file with columns `invoice_id,total_due,paid,tax_paid`
(any of the numeric columns may be blank/missing). For each invoice write a JSON
object:
```json
{
  "<invoice_id>": {"total_inclusive": <float>, "tax_amount": <float|null>, "conflict": <bool>}
}
```
Where `total_inclusive` is `total_due` when present, otherwise `paid` when
present, otherwise `null`; `tax_amount` is `tax_paid` when present else `null`;
`conflict` is `true` exactly when **both** `total_due` and `paid` are present
and they differ by at least `0.005`. Keys are sorted by `invoice_id`.

### `series HOURLY [-o OUT] [--delim TAB]`
`HOURLY` is a TAB file with columns `hour,value` where `hour` looks like
`YYYY-MM-DD HH:MM` and `value` is numeric or blank. Rebuild the **full hourly
range** from the smallest to the largest hour that appears (inclusive, one step
per hour). For every hour in that range produce `hour,value` sorted ascending,
as a CSV with rows for **all** steps. A step's value is filled by **linear
interpolation between the nearest known (non-empty) neighbours in time**. If a
value is missing before the first known value (leading boundary) use that first
known value; if after the last known value (trailing boundary) use that last
known value. Only numeric, well-formed `YYYY-MM-DD HH:MM` hours take part. If
there are no usable rows the output has just the header.

### `papers LIST [-o OUT] [--delim ,]`
`LIST` has a `title` and a `doi` column (plus other columns that must be
ignored). Emit **one JSON Lines record per paper**, in original order, where
each line is a JSON object with **exactly two fields**:
```json
{"title": "<title>", "doi": "<doi>"}
```
No extra fields, nothing else on the line.

---

## Recommended local validation

Write `/app/clean.py`, then produce the deliverables:

```bash
python3 /app/clean.py organize /app/data/departments.csv \
    /app/data/employees.csv /app/data/projects.csv -o /app/result.json
python3 /app/clean.py topk /app/data/requests.csv -k 5 -o /app/top.tsv
```

Exercise each other subcommand against the `sample_*` fixtures (e.g.
`python3 /app/clean.py grouped /app/data/sample_sales.csv --category category --vars revenue in_stock`).
Ensure the tool also parses a **fresh** same-schema input without a traceback.

## Constraints

* All authored code lives under `/app`; deliverables are exactly
  `/app/clean.py`, `/app/result.json`, `/app/top.tsv`.
* Do **not** touch anything under `/tests` (mounted read-only) and never read it.
* Everything runs offline in one container (no network, no services). Rely only
  on the Python standard library plus `pandas`/`numpy` if helpful.

## How you will be graded (read-only)

The verifier re-invokes `/app/clean.py` on hidden inputs and independently
recomputes: the nested org JSON (strict nesting, sorted-by-key, no duplicates,
correct dept/employee/project cardinality); the entity-filtered record set
(exact membership incl. case/account variants, no other companies); the top-k
counts and tie ordering; the boolean-column-detected grouped aggregations and
means (empty-cell handling); the per-invoice totals/conflicts and null tax
fallbacks; the gap-free interpolated hourly series (boundary fallback + linear
interp); and the exactly-two-field JSON Lines records. It also confirms the
delivered `/app/result.json` and `/app/top.tsv` match what running your tool on
the shipped data produces. Any missing deliverable, crash, wrong number, wrong
ordering, or extra/missing row fails the run.