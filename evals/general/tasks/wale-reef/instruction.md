# wale-reef: a memory-bounded analytical pipeline over a Parquet warehouse

You are an analytics engineer handed a Hive-partitioned Parquet **fact table**
of retail transactions: `/app/warehouse` (~630 MB across twelve monthly
partitions, 48M rows). Your job is to write **one self-contained Python
program**, `/app/run.py`, that computes the analytical pipeline specified below
over **any** warehouse with the same layout and schema — the shipped one and
fresh ones the verifier mounts under `/tests` — and emits a materialised
summary table plus a report. It is a reusable tool driven purely by
command-line arguments; it must not be a one-off for the shipped paths.

## Environment

- DuckDB 1.5.5 is installed (Python API). Only the Python standard library and
  `duckdb` may be used. Network is unavailable; do not install packages.
- `/app/warehouse` is **read-only input**. Never write into it.
- The CPU quota is 1 core. Set `threads=1` in your DuckDB session; the image
  already pins OMP/OPENBLAS/MKL/NUMEXPR threads to 1.

## Command line

```
python3 /app/run.py <WAREHOUSE> <OUTDIR>
```

Exactly two positional arguments.

- `WAREHOUSE`: a directory containing `transactions/` with Hive partition
  directories `year=YYYY/month=MM/*.parquet`. Use a recursive glob, since a
  partition may hold more than one Parquet file.
- `OUTDIR`: where the pipeline writes its three outputs (created if missing).
  The pipeline must write nothing outside `OUTDIR` except transient temp/spill
  files under `/tmp`.

## Fact-table schema (each Parquet file)

| column            | type      |
|-------------------|-----------|
| txn_id            | BIGINT    |
| ts                | TIMESTAMP |
| region            | VARCHAR   |
| category          | VARCHAR   |
| units             | INT       |
| unit_price_cents  | INT       |
| amount_cents      | BIGINT    |

Monetary values are integer **cents** throughout. No floating-point values
appear anywhere in the outputs.

## What the pipeline must compute

### Stage A — per-transaction analytics (window functions over the full fact table)

For every fact row compute:

- `pct_tile`: the row's value-percentile bucket within its region: DuckDB's
  `NTILE(100)` applied to each region's rows ordered by
  `(amount_cents ASC, txn_id ASC)`. A value in 1..100.
- `running_amount_cents`: the running total of `amount_cents` within its region
  in `txn_id` order: `SUM(amount_cents) OVER (PARTITION BY region
  ORDER BY txn_id)`.

### Stage B — the materialised summary table

Aggregate Stage A into one row per `(region, day, pct_tile)` where
`day = CAST(ts AS DATE)`:

- `txns` — `COUNT(*)`
- `units` — `SUM(units)`
- `amount_cents` — `SUM(amount_cents)`
- `rolling_avg_cents` — the mean of `amount_cents` over the current day and the
  previous 6 days (ordered by `day`) within the same `(region, pct_tile)`:
  `AVG(amount_cents) OVER (PARTITION BY region, pct_tile ORDER BY day
  ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)`, rounded to the nearest whole cent
  with DuckDB's `ROUND()` and cast to BIGINT.
- `running_total_cents` — `SUM(amount_cents) OVER (PARTITION BY region, pct_tile
  ORDER BY day ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)`.
- `rank_by_txns` — `RANK() OVER (PARTITION BY region, pct_tile
  ORDER BY txns DESC)`.

### Outputs written to `OUTDIR`

1. **`daily_summary.csv`** — the materialised summary table. Header line
   exactly:
   `region,day,pct_tile,txns,units,amount_cents,rolling_avg_cents,running_total_cents,rank_by_txns`
   One row per `(region, day, pct_tile)` present. Rows sorted by
   `(region ASC, day ASC, pct_tile ASC)`. `day` as ISO `YYYY-MM-DD`. Every
   other field a plain decimal integer. LF line endings, no blank lines, no
   surrounding quoting (values contain no commas, quotes or newlines).

2. **`daily_summary.parquet`** — the same table materialised to Parquet
   (`COPY ... TO ... (FORMAT PARQUET)`), so a later stage can run DuckDB
   queries against it without recomputing Stage A/B.

3. **`report.json`** — a UTF-8 JSON object, `indent=2`, with **exactly** the
   following keys in exactly this order:
   - `total_txns` — number of fact rows
   - `total_units` — sum of `units` over all fact rows
   - `total_amount_cents` — sum of `amount_cents` over all fact rows
   - `distinct_days` — count of distinct `day` values
   - `active_regions` — count of distinct `region` values
   - `largest_day_amount_cents` — the largest per-(region, day) sum of
     `amount_cents`
   - `top_category` — the `category` with the largest `SUM(amount_cents)`
     overall; ties broken by lexicographically smallest category name
   - `top_tile_txns` — number of fact rows with `pct_tile = 100`
   - `leaderboard` — an array of exactly 5 objects, the top 5 regions by total
     `amount_cents` (ties broken by `region` ascending), each
     `{"rank": ..., "region": ..., "amount_cents": ...}` where `rank` is
     `RANK() OVER (ORDER BY total DESC)` over all regions

   All numeric values are JSON integers; the file ends with a single trailing
   newline.

## The memory ceiling

Create `/app/memory_claim.json` containing exactly
`{"ceiling_mb": N}` with `N` an integer, `128 <= N <= 512`.

The verifier measures the pipeline's **peak resident set size** (the
`ru_maxrss` the OS attributes to the run) while it runs `/app/run.py` — once
on the visible warehouse and once per hidden partition — and the declared
ceiling must hold: **every** run's peak must be at most `N` MB. The
measurement covers the run as a whole, including any processes the pipeline
itself spawns, so the DuckDB computation must happen inside the measured
run; it cannot be hidden in an unmeasured helper process.

This is the crux of the task. The shipped warehouse is ~630 MB of Parquet;
run with DuckDB's default session settings, this pipeline's peak RSS is on
the order of **3.5 GB** — well over the budget above. Producing byte-exact
outputs under a ceiling of at most 512 MB is only possible if the DuckDB
session actually executes in its documented bounded-memory mode: the fact
scan stays streaming, and intermediate windows, sorts and aggregates spill
to disk instead of being materialised in RAM. The concrete session
configuration that achieves this is yours to determine — the DuckDB Python
API documents the options — and yours to validate by measurement.
Choose `N` from measurement, not intuition: run your pipeline, observe its
peak RSS (e.g. with the `resource` module or `/usr/bin/time -v`), and declare
an honest ceiling with headroom for run-to-run variance.

## Constraints

- `/app/run.py` must be the only program: single file, stdlib + `duckdb` only,
  driven entirely by `sys.argv`. No hard-coded warehouse paths, region names,
  categories, dates, row counts or partition lists — hidden partitions use
  different seeds and periods with the same schema.
- Byte-exactness: the verifier compares your outputs (canonically) against
  reference outputs computed from the definitions above. Window semantics —
  NTILE bucket assignment on ties, ROUND half-away-from-zero, RANK tie
  handling, ordering — must match DuckDB's exactly, because the reference is
  computed with DuckDB.
- Do not weaken the task: `pct_tile` is NTILE(100), not percent_rank or a
  manual histogram; the summary aggregates exactly the columns above.

## Deliverables

- `/app/run.py`
- `/app/output/daily_summary.csv`
- `/app/output/daily_summary.parquet`
- `/app/output/report.json`
- `/app/memory_claim.json`

`/app/output/` is the result of running your own pipeline once yourself:

```
python3 /app/run.py /app/warehouse /app/output
```

The verifier re-runs `/app/run.py` against `/app/warehouse` and against hidden
fixtures and checks byte-exact outputs, the materialised Parquet table, and
the memory ceiling on every run.