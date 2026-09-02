# Explain query plan

In `/app` there is a SQLite database `store.db`. It has a table `sales`:

```
sales(id INTEGER PRIMARY KEY, region TEXT, amount REAL)
```

An index `sales_region` exists on `sales(region)`.

## Your task

Write a Python 3 script `/app/explain.py` that:

1. connects to `/app/sales.db`,
2. runs `EXPLAIN QUERY PLAN` on the exact query
   `SELECT * FROM sales WHERE region = 'East'`,
3. parses each returned plan row (`id`, `parent`, `notused`, `detail`) by
   reading the `detail` text. The plan row(s) are the ones whose `id` equals
   the row index (0-based) within the returned rows (i.e. the top-level plan
   step has the minimal `id`).
4. Determines whether an index is used by testing if any `detail` string
   contains the substring `USING INDEX`. If so, extract the index name: the
   identifier that immediately follows `USING INDEX ` up to the next
   whitespace or `(`.
5. Writes `/app/plan.json` with exactly:
   ```json
   {"uses_index": true, "index_name": "sales_region", "plan": ["SEARCH sales USING INDEX sales_region (region=?)"]}
   ```
   where `uses_index` is a bool, `index_name` is the extracted name string (or
   `null` if no index is used), and `plan` is the list of `detail` strings in
   plan-id order.

Run `/app/explain.py` so `/app/plan.json` exists with the correct values. The
verifier independently runs `EXPLAIN QUERY PLAN` on the same query and database
and checks the JSON matches.