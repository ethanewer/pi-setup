# Schema reconciliation

Two files describe the same customers with **different schemas**:

- `/app/old.tsv` — legacy tab-separated file. Header: `cust_id`, `full_name`, `contact_email`, `city`.
- `/app/new.csv` — current comma-separated file. Header: `id`, `name`, `email`, `phone`, `city`.

Customers are keyed by customer id (`cust_id` in the old file, `id` in the new file). Some customers appear in both files, some only in one, and where a customer appears in both the values may have changed between the legacy and current records.

Write a Python program at `/app/reconcile.py` that merges the two files into the **new schema** and reports conflicts, writing `/app/reconciled.json`.

## Rules

1. Parse both files (skip the header, strip whitespace from every field).
2. **Records** — one output record per customer id (the union of both files), each with keys `id`, `name`, `email`, `phone`, `city`:
   - If a customer is in the **new** file, its `name`, `email`, `phone`, `city` come from the new file.
   - Otherwise (only in the old file), `name`, `email`, `city` come from the old file and `phone` is `null`.
   - `id` values are integers; the file order is irrelevant — sort the records by `id` ascending.
3. **Conflicts** — for a customer that appears in **both** files, compare the old and new values of the `email` and `city` fields. A conflict exists when **both** the old and new values are non-empty **and** they differ. For each such difference append:
   ```json
   {"id": <int>, "field": "email"|"city", "old": "<old value>", "new": "<new value>"}
   ```
   (The new value still wins in the `records` output.) Sort conflicts by `id` ascending; for the same id, the `city` conflict (if any) comes before the `email` conflict (if any).

## Output format

Write `/app/reconciled.json`:

```json
{
  "records": [
    {"id": 1, "name": "Carol Diaz", "email": "carol@new.example", "phone": "555-0001", "city": "Oslo"}
  ],
  "conflicts": [
    {"id": 3, "field": "city", "old": "Almaty", "new": "Madrid"}
  ]
}
```

`records` must contain exactly one entry per customer id, sorted by `id` ascending. Only the Python standard library is required. Run the program so `/app/reconciled.json` exists.