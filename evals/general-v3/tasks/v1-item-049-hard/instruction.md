# Item-049 (hard) — Configuration-driven customer reconciliation

Three raw customer files overlap, but you may **not** assume the order or
meaning implied by their filenames. The authoritative precedence is declared in
a config file. Your job is to produce one canonical Parquet table by parsing
that config, normalizing messy values, reconciling per field, and proving the
row count and output schema.

## Inputs (read-only), under `/app/data/all_sources/`

- `master_customers.csv` — CSV with header
  `customer_id,full_name,email,phone,region,status,created_at,loyalty_tier`.
  Messy: blank cells and sentinel strings (`NULL`, `N/A`) appear where values are
  missing, and letter-case / whitespace are inconsistent.
- `overrides.json` — JSON array of objects with the same logical fields; JSON
  `null` means missing. Some phone numbers are formatted with spaces (e.g.
  `555 310 4455`) and must normalize to the same canonical form as
  `555-3104455`.
- `attic_snapshot.parquet` — same fields; missing values are Parquet nulls.
- `/app/data/precedence.json` — maps each source **filename** to a precedence
  rank: **smaller rank = higher precedence**. Read this file; do not guess order
  from filenames. Example:
  `{"attic_snapshot.parquet": 1, "overrides.json": 2, "master_customers.csv": 3}`

## Normalization contract

Apply to every source before merging:

- `customer_id`: strip, then uppercase (the canonical key).
- `full_name`: strip.
- `email`: strip, then lowercase.
- `phone`: strip to digits only (`re.sub(r'[^0-9]', '', v)`); empty -> missing.
- `region`, `status`, `loyalty_tier`: strip; treat `""`, `"NULL"`, `"N/A"`,
  `"NA"`, `"NaN"` (any casing) as missing.
- `created_at`: strip.

## Merge rule (per field, per customer)

Order sources by ascending precedence rank. For each customer id and each
column, the canonical value is taken from the first (highest-precedence) source
that has a non-missing normalized value. If no source has one, the cell is null.

There are exactly **30** distinct customers. Output the table sorted ascending
by `customer_id`.

## Deliverable

Write `/app/reconcile.py` that reads the inputs and config, and writes
`/app/output/customers.parquet` with the 8 canonical columns in this exact order
(all string type, null for missing):

```
customer_id, full_name, email, phone, region, status, created_at, loyalty_tier
```

Also write `/app/output/manifest.json`:

```json
{"row_count": 30, "distinct_ids": 30}
```

Run: `cd /app && python3 reconcile.py`.

## Anti-footguns (be adversarial with yourself)

- The filename `master_customers.csv` says "master", but it is only rank 3 if
  `precedence.json` says so. Trust the config, not the name.
- JSON `null` is not the string `"NULL"`.
- Blank cells and sentinel strings are both missing; never let them clobber a
  real value from a higher-precedence source.
- A logical id may carry outer spaces / lowercase across sources; all
  normalizations collapse to one canonical key, and the row is written once.

## Success criteria (verifier)

The verifier independently applies this contract from the raw files and asserts:
- `manifest.json` says row_count=30 (distinct_ids=30);
- the parquet has exactly the 8 schema columns in order;
- every field equals its recomputed canonical value, after both tables are
  sorted by `customer_id`;
- no `customer_id` appears twice.

Do not modify anything under `/app/data/`. Creating `/app/output/` is required.