# Raven data-mart close-out

## Objective

The **Raven** analytics group is shutting down a data-mart and needs one Python
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

- create `<output_dir>` (and its subdirectories),
- write every output artifact described below into `<output_dir>`,
- exit with status `0`, and
- print exactly this line on stdout when everything has succeeded:

```
RAVEN-CLOSE-OUT COMPLETE: STATUS=OK
```

## Input directory layout

Every run is given an `<input_dir>` containing these files (any of them may
contain blank lines and stray surrounding whitespace around values; treat
column headers case-insensitively and strip surrounding whitespace/quotes from
header names):

| file | contents |
|------|----------|
| `activity.csv` | columns `period, severity, n_events, is_critical, is_escalated` |
| `departments.csv` | columns `dept_id, dept_name` |
| `employees.csv` | columns `emp_id, emp_name, dept_id, is_active` |
| `projects.csv` | columns `proj_id, emp_id, proj_title, category, product_id` |
| `aliases.csv` | columns `alias, canonical_id` |
| `contacts.csv` | columns `record_id, owner_name, owner_id, amount` |
| `target.txt` | a single line naming the target entity variant |
| `requests.csv` | a `url` column (may carry extra columns) |
| `series.csv` | columns `hour, value` (an hourly series) |
| `series_span.txt` | two integers: `start end` (inclusive hour range) |
| `papers.csv` | columns `paper_id, title` |

Never modify, rename, or delete anything inside `<input_dir>`. Treat values as
trimmed: surrounding whitespace on any cell is insignificant for comparison
(this applies to the output artifacts as well — e.g. `amy.pond` and
` amy.pond` are equivalent, and header names are matched case-insensitively).
The first non-blank line of each CSV file is its header row (names are read
case-insensitively, with surrounding whitespace/quotes stripped); the
remaining non-blank lines are data rows, and blank lines anywhere are
ignored. If an input file is missing or empty, treat its data as empty (do
not crash).

## Deliverables (written into `<output_dir>`)

### 1. `aggregated.csv` — grouped aggregation with boolean-column detection
From `activity.csv`, **detect** which of the non-key columns
(`is_critical`, `is_escalated`) are boolean. A column is boolean when *every*
non-empty cell in it belongs to the boolean vocabulary
`true/false/yes/no/1/0/y/n/t/f` (case-insensitive); a column containing any
non-vocabulary token (e.g. `maybe`, `urgent`, blank-only columns are dropped
too) is **not** boolean and is excluded. Inside `is_critical`,
`is_escalated`, `is_critical` etc. truthy means `true/yes/1/y/t`.

Group rows by `(period, severity)` (left normalized). For each group emit one
row: `period,severity,count,events,<bool1>_true,...,<boolN>_true` where
`count` is the number of rows, `events` is the sum of the integer `n_events`
(rows whose `n_events` is not an integer contribute 0), and for each detected
boolean column in order, `<col>_true` is the number of rows in which that column
is truthy. Rows sorted by `period` ascending, then `severity` ascending. Only
detected boolean columns appear (in the order `is_critical` before
`is_escalated`).

### 2. `summary.csv` — a fixed-shape table
A compact version of the same grouping: header `period,severity,count`, one row
per `(period,severity)` group (same order as above) with its `count`. This table
must have **exactly** a header plus the set of ordered `(period,severity,count)`
rows, no extra columns, no blank lines.

### 3. `result.json` — nested `departments -> employees -> projects` graph
From `departments.csv`, `employees.csv`, `projects.csv`, build:

```json
{
  "eng": {
    "dept_name": "Engineering",
    "employees": {
      "e101": {
        "emp_name": "Ada",
        "is_active": true,
        "projects": {
          "p1": { "proj_title": "Kernel", "category": "core", "product_id": "PD-1" }
        }
      }
    }
  }
}
```

- one key per distinct `dept_id`, each holding `dept_name` and its `employees`;
- one key per employee, placed under the dept named in that employee's row;
  `is_active` is the boolean interpretation of `is_active`;
- each project is attached under the employee whose `emp_id` it references;
- employees whose `dept_id` is not among the departments, and projects whose
  `emp_id` is not an emplaced employee, are skipped;
- **no duplicates**: repeating a dept/employee/project id more than once must
  produce a single entry (later identical rows do not create extra nodes);
- the JSON must be written with 2-space indentation and keys ordered ascending
  (`json.dump(…, sort_keys=True)` semantics): dept names and ids, employee ids,
  project ids all sorted by key.

### 4. `projects_grouped.csv` — table groupable by category & product-id
From `projects.csv`, group by `(category, product_id)` and count how many
project rows fall in each pair. Header `category,product_id,count`, rows sorted
by `category` ascending then `product_id` ascending. Every distinct pair is
emitted exactly once; a pair seen multiple times collapses to one row with the
total count.

### 5. `filtered.csv` — target entity across name/identifier variants
Pick the **target entity** from `target.txt` and resolve it to a **canonical id**:

1. if the target equals any `canonical_id` in `aliases.csv`, that is the id;
2. else if the target equals any `alias` in `aliases.csv`, use that row's
   `canonical_id`;
3. else if any contact has `owner_id` equal to the target, use that id;
4. else if any contact has `owner_name` equal to the target, use that contact's
   `owner_id`;
5. else there is no target record.

Keep every contact row whose `owner_id` equals the resolved canonical id. If no
target resolved (or blank `target.txt`, or file missing), emit **header only**,
no data rows. Output keeps all `contacts.csv` columns (in the original header
order; cell values are copied as-is from the matched rows, and surrounding
whitespace on any cell is insignificant), rows sorted by `record_id` ascending.
Matching is case-insensitive and trims surrounding whitespace on both the
target and the compared values.

### 6. `top.tsv` — top-5 request URLs ranked by frequency
From `requests.csv`, count how many times each non-blank `url` occurs (trim
surrounding whitespace from each url before counting; ignore entirely-blank
urls). Take the top 5 distinct URLs by frequency **descending**, ties broken by
url **ascending**. If fewer than 5 distinct URLs exist, emit only those. Write a
header line `rank<TAB>url<TAB>count` followed by `rank` data lines
`<rank><TAB>url<TAB>count` (`rank` is 1-based, `count` the integer frequency).

### 7. `series_filled.csv` — hourly series with interpolation & boundary fallback
From `series.csv`, valid `(hour, value)` records: `hour` parsable as an integer
and `value` a parsable number; ignore rows with a bad hour or empty/non-numeric
value. If an hour repeats, the **last** occurrence wins. Fill every hour in the
inclusive range `[start, end]` read from `series_span.txt`:

- hour present in the data → its value;
- hour missing but there are known hours both below **and** above it within the
  data → **linear interpolation** between the nearest known hour below and the
  nearest known hour above;
- hour missing before the first known hour or after the last known hour →
  **boundary fallback** to the nearest known value (forward-fill for a leading
  hole before the first known hour, backward-fill for a trailing hole);
- if exactly **one** known hour exists, every hour in the range takes that value
  (boundary fallback);
- if there are **no** valid known hours (or `series_span.txt` is missing/invalid
  /`start`>`end`), emit the header `hour,value` only.

Header `hour,value`, hours ascending, values rounded to 6 decimal places (the
rounded numeric value is what is verified — presentations such as `10.0` and
`10.000000` are both accepted).

### 8. `papers.jsonl` — JSON Lines, exactly two fields per paper
One JSON object **per paper**: `{"id": "<paper_id>", "title": "<title>"}`
containing **exactly** the two keys `id` and `title`, one record per line, in
the same order as the rows. Omit nothing; a blank `paper_id` or `title` is kept
as the empty string.

## Edge cases you must handle generally

Hidden runs use genuinely different data and will probe: boolean columns whose
vocabulary is broken (a `maybe`/`urgent`/blank token) so `boolean-column
detection` must drop them, duplicate ids (dedup), empty inputs, whitespace and
case variation in target/url/values, a sole known hour and a fully-empty series,
`start/end` ranges that exceed the known hours or are invalid, a target resolved
only through an alias or directly via `owner_id`/`owner_name`, empty filtered /
paper sets, top-k ties, and 2-combinations of the above.

## What you must deliver

1. `/app/clean.py` — the program described above.
2. Run it against the provided sample input so the deliverables land in `/app`:

```
python3 /app/clean.py /app/data /app
```

This must leave `/app/aggregated.csv`, `/app/summary.csv`, `/app/result.json`,
`/app/projects_grouped.csv`, `/app/filtered.csv`, `/app/top.tsv`,
`/app/series_filled.csv`, and `/app/papers.jsonl` present under `/app`. Do not
delete `/app/data`; it is needed again later. Your `/app/clean.py` will be
re-run on **hidden** input directories that follow the same layout.

## Success criteria

The pipeline must run on any such input directory, exit `0`, print the
completion line, and produce every artifact in the formats above. The verifier
re-runs `/app/clean.py` on the hidden directories and therefore independently
recomputes every artifact.