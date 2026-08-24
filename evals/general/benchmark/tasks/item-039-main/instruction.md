# Daily sales log aggregation & reconciliation

A retail firm stores one CSV file per calendar day under `/app/logs/`. Each file is named
`sales_YYYY-MM-DD.csv` and has the same header row:

```
transaction_date,store,region,amount,currency
```

Each data row is a single transaction. `transaction_date` is an ISO-8601 timestamp in UTC
(always ends with `Z`), e.g. `2024-06-01T09:14:00Z`. `amount` is a decimal money value in
`currency` (always `USD`). Some rows are **malformed** and must be skipped (see below).

Two control files also exist:

- `/app/config.txt` — key=value lines describing the report window:
  ```
  timezone=UTC
  start=2024-06-01
  end=2024-06-03
  ```
- `/app/totals.csv` — the authoritative per-region expected totals, used for
  reconciliation. Header: `region,expected_total`. Example:
  `East,27.75`

## Reporting window (define inclusion boundaries explicitly)

A report row is aggregated per **calendar date** (in the configured `timezone`). Because
`timezone` is `UTC` here, a transaction's report date equals the UTC date of
`transaction_date`.

The window is **start-inclusive, end-exclusive by local calendar date**:
`start <= local_date < end`. Transactions whose local date is strictly before `start`, or
greater than or equal to `end`, are **excluded** from the report.

## Malformed records (skip and record)

A row is malformed and must be excluded from all totals if any of these hold:

- it does not have exactly 5 comma-separated fields (e.g. a trailing/full row),
- `amount` is not parseable as a decimal number,
- `transaction_date` does not parse as ISO-8601 UTC (it will always end in `Z`),
- `currency` is not `USD`.

When you skip a malformed row, append one line to `/app/malformed.log` with the format:

```
<filename>:<1-based line number>:<reason>
```

where `<reason>` is one of `field_count`, `amount`, `date`, `currency`. The first line of
a file (the header) is line 1; the first data row is line 2, etc.

## Deliverables (write these files)

### 1. `/app/report.csv`

Aggregate the included (valid, in-window) rows by `(local date, region)`:

```csv
date,region,amount,row_count
2024-06-01,East,15.75,2
2024-06-01,West,20.00,1
```

- `date` is `YYYY-MM-DD`.
- `amount` is the sum of included `amount` values for that (date,region), rounded to 2
  decimals.
- `row_count` is the number of included rows.
- Rows sorted ascending by `date`, then by `region` (case-sensitive lexicographic).

### 2. `/app/reconciliation.csv`

For **every** region that appears in `/app/totals.csv`:

```csv
region,expected_total,reported,difference,status
East,27.75,27.75,0.00,match
```

- `reported` = the sum of `amount` for that region across all included rows
  (0.00 if the region has no included rows in the window).
- `difference` = `expected_total - reported` rounded to 2 decimals.
- `status` = `match` when `abs(difference) < 0.001`, else `mismatch`.
- Sorted by `region` (case-sensitive lexicographic).

### 3. `/app/REPORT_META.json`

```json
{
  "start": "2024-06-01",
  "end": "2024-06-03",
  "timezone": "UTC",
  "regions_aggregated": ["East", "North", "West"],
  "total_rows": 5,
  "reconciled": true
}
```

- `regions_aggregated`: the distinct regions present in report.csv, sorted ascending.
- `total_rows`: the total row_count summed over the whole report.
- `reconciled`: `true` iff **every** row in reconciliation.csv has `status == "match"`.

## Workflow

1. Inspect `/app/logs/`, `/app/config.txt`, `/app/totals.csv`.
2. Write a Python script `/app/aggregate.py` that computes all four deliverables from
   those inputs and writes them.
3. Run it, verify the outputs by hand (every malformed row excluded, boundary dates
   excluded, and `reconciled` reflects the totals comparison).

Leave `/app/aggregate.py` and all four outputs in place when you are done.