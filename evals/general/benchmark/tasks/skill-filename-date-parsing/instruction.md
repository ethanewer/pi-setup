# Parse dates embedded in filenames

`/app/logs/` contains log files named with an embedded date in this exact
pattern:

```
app-YYYY-MM-DD.log
```

for example `app-2024-03-14.log`. The dates are valid (spaced correctly for the
month; the four digits years, two-digit months and days are `0`-padded). The
directory contains:

```
app-2024-11-02.log
app-2023-01-15.log
app-2024-07-30.log
app-2023-12-31.log
app-2024-02-29.log
```

## Your task

Write a Python 3 script `/app/parsedates.py` that:

1. scans the files in `/app/logs/`,
2. for each `.log` file, extracts the date `YYYY-MM-DD` as a `(year, month, day)`
   tuple,
3. sorts the files ascending by date (earliest first; on a tie, by filename
   lexicographically),
4. writes `/app/order.json` — a JSON array of the file *names* (just the
   basename, e.g. `"app-2024-11-02.log"`) in sorted order.

Run the script so the JSON exists. The verifier parses the same filenames
independently and compares the full ordered list.