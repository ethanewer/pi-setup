# Multi-timezone daily sales log aggregation & reconciliation

A retail firm stores one CSV file per calendar day under `/app/logs/`. Each file is named
`sales_YYYY-MM-DD.csv` and has the same header row:

```
transaction_date,store,region,amount,currency
```

`transaction_date` is an ISO-8601 timestamp in **UTC** (always ends with `Z`), e.g.
`2024-06-01T09:30:00Z`. `store` is a free-text store name: it may contain **commas and
quotes**, so you MUST parse these files as real CSV (a robust CSV reader — never a naive
`str.split(',')`). `amount` is a decimal money value in `currency` (always `USD`). Some
rows are **malformed** and must be skipped.

Two control files also exist:

- `/app/config.txt` — key=value lines describing the report window:
  ```
  timezone=America/New_York
  start=2024-06-01
  end=2024-06-04
  ```
- `/app/totals.csv` — the authoritative per-region expected totals.
  Header: `region,expected_total`.

## Your job: build the daily regional report AND reconcile it against the ledger.

### 1. Local calendar date (timezone bucketing)

A transaction belongs to the **local calendar date** of `transaction_date` in the
configured timezone. The configured timezone is `America/New_York`, which in this dataset
is Eastern Daylight Time, i.e. **UTC-4** (always; treat the offset as fixed at -4 hours for
bucketing). This matters: a UTC timestamp like `2024-06-02T01:30:00Z` falls on **local
date 2024-06-01** (21:30 the evening before), and must be bucketed under `2024-06-01`.

### 2. Inclusion window (define inclusion boundaries explicitly)

Include a transaction if and only if

```
start <= local_date <= end - 1 day      (i.e. start inclusive, end exclusive by local date)
```

Transactions with local date `< start` or `>= end` are excluded.

### 3. Malformed rows

A row is malformed and must be excluded from all totals if any of these hold:

- its field count (after proper CSV parsing) is not exactly 5,
- `amount` is not parseable as a decimal number,
- `transaction_date` does not parse as an ISO-8601 UTC timestamp ending in `Z`,
- `currency` is not `USD`.

Append one line to `/app/malformed.log` per skipped row:

```
<filename>:<1-based line number>:<reason>
```

with `<reason>` one of `field_count`, `amount`, `date`, `currency`. Rows that were
**outside the window** are the only valid rows not summed — do **not** log those as
malformed.

## Deliverables

### 1. `/app/report.csv`

Aggregate included (valid, in-window) rows by `(local date, region)`:

```csv
date,region,amount,row_count
2024-06-02,East,21.99,2
```

- `date` = the **local** `YYYY-MM-DD`.
- `amount` = sum of included amounts for that (date, region), rounded to 2 decimals.
- `row_count` inclusive count.
- Sorted ascending by `date`, then `region` (case-sensitive lexicographic).

### 2. `/app/reconciliation.csv`

For **every** region in `/app/totals.csv`:

```csv
region,expected_total,reported,difference,status
East,33.49,33.49,0.00,match
North,7.50,7.00,0.50,mismatch
```

- `reported` = per-region total across the window (0.00 if absent).
- `difference` = `expected_total - reported`, rounded to 2 decimals.
- `status` = `match` if `abs(difference) < 0.001`, else `mismatch`.
- Sorted by `region` (case-sensitive lexicographic).

### 3. `/app/REPORT_META.json`

```json
{
  "start": "2024-06-01",
  "end": "2024-06-04",
  "timezone": "America/New_York",
  "regions_aggregated": ["East", "North", "West"],
  "total_rows": 8,
  "reconciled": false
}
```

`reconciled` is `true` iff **every** reconciliation row has `status == "match"`.
(Here the posted totals contain deliberate discrepancies — report them truthfully, and
`reconciled` will be `false`.)

### 4. `/app/malformed.log`

As described above, one line per skipped malformed row.

## Workflow

1. Inspect `/app/logs/`, `/app/config.txt`, `/app/totals.csv` (including a file whose
   timestamps straddle the UTC/local date boundary and a quoted store name containing a
   comma).
2. Write `/app/aggregate.py`, run it, and hand-verify: quoted fields parse correctly,
   malformed rows are skipped and logged, boundary rows are bucketed to the correct local
   date, out-of-window rows are excluded, and reconciliation reflects the totals file.

Leave `/app/aggregate.py` and all four outputs in place when you are done.