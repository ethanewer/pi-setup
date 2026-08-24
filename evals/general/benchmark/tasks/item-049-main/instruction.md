# Item-049 (medium) — Reconcile heterogeneous customer records into one

A migration team has handed you three raw, overlapping customer-record files that
describe the same population. You must reconcile them into a single canonical
Parquet file with a fixed schema and an exact row count, under a documented
source-precedence rule.

## Inputs (read-only)

- `/app/data/all_sources/master_customers.csv` — **highest** precedence. A CSV
  with header `customer_id,name,email,phone,region,status,created_at`. Blank
  fields appear as empty strings where a value is genuinely unknown.
- `/app/data/all_sources/legacy_customers.json` — **middle** precedence. A JSON
  array of objects with the same logical fields. Not every object has every
  field; a JSON `null` value means missing.
- `/app/data/all_sources/archive_snapshot.parquet` — **lowest** precedence. Same
  logical fields; missing values are Parquet nulls.

## Reconciliation contract (follow exactly)

1. **Normalize identifiers.** Trim whitespace and uppercase every
   `customer_id`. Keys that merely differ in case or padding denote the SAME
   customer (e.g. `c02` and `C02` are the same).

2. **Treat missing uniformly.** Across all sources, an empty string, a JSON
   `null`, and a Parquet null are all “missing”. A missing value is treated as
   absent.

3. **Source precedence, per field.** For one customer, the canonical value of
   each field comes from the **highest-precedence source that supplies a
   non-missing value** for that field. If no source has a value, the output cell
   is null.

4. **Union row count.** Every distinct customer id across all three sources is
   exactly one output row. There are exactly **17** distinct customers.

5. **Output schema (exact names and order; all string type).**
   `customer_id, name, email, phone, region, status, created_at`
   All seven columns are string-typed. Cells that are missing become null.

6. **Deterministic order.** Sort the output rows ascending by `customer_id`,
   so the same input always yields the same file.

## Deliverable

Write `/app/reconcile.py` (Python + pandas/pyarrow) that reads the three inputs
above and writes `/app/output/customers.parquet`.

Run it:

```bash
cd /app && python3 reconcile.py
```

## Self checs before finishing

- The output has exactly 17 rows and the 7 expected columns in order.
- Re-run it and diff — two runs must produce the same bytes.
- Reason about `C21`: decide, field by field, which source finally supplies
  `email`, `phone`, `region`, and `status`, and confirm the code agrees.

## Success criteria (verifier)

The verifier independently recomputes the expected table from the same three
inputs under this contract and checks the produced file:
- the exact column set/order;
- exactly 17 rows;
- every field matches the recomputed reconciliation after sorting both tables by
  `customer_id`.

Do not modify anything under `/app/data/`. Creating `/app/output/` is expected.