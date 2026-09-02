# Summarize a CSV of sales

`/app/sales.csv` is a comma-separated file with a header row. The data columns are:

```
item,amount
```

where `item` is a string (may contain spaces, no commas) and `amount` is an integer. Example:

```
item,amount
widget,10
gadget,25
```

Write a Python program `/app/analyze.py` that:

1. Reads `/app/sales.csv` using Python's standard `csv` module.
2. Computes, over all data rows:
   - `count`: number of data rows (excluding the header),
   - `total`: sum of the `amount` column,
   - `avg`: `total / count` as a float.
3. Writes `/app/stats.json`:

```json
{"count": <int>, "total": <int>, "avg": <float>}
```

Then run `/app/analyze.py` so `/app/stats.json` exists. The verifier recomputes the same statistics from the CSV and compares them exactly (avg compared with `1e-9` tolerance).