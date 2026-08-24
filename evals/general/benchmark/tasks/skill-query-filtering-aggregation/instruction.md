# Query filtering + aggregation

`/app/transactions.tsv` is a TSV (tab-separated) table with a header: `id`, `category`, `amount`, `status`. Amounts are integers; status is `active` or `cancelled`.

Your task is to perform a query-style filter-then-aggregate transformation and write the result as compact JSON:

1. **Filter**: keep only rows whose `status` is `active`.
2. **Aggregate**: for each distinct `category` (sorted by category name ascending), compute the sum of the `amount` values across the kept rows.
3. Write `/app/report.json` containing a JSON object mapping each category (string) to its total amount (integer).

The exact expected totals are deterministic. Example output shape:
```json
{"books":55,"electronics":150,"stationery":20}
```

Write your solution as `/app/query.py` and run it so `/app/report.json` is produced. Do not include the id/product columns in the output.
