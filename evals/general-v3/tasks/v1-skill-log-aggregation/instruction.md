# Log aggregation

`/app/logs/` contains three application log files: `app1.log`, `app2.log`, `app3.log`. Every line has the format:

```
HH:MM:SS LEVEL message...
```

where `LEVEL` is one of `INFO`, `WARN`, or `ERROR`.

Aggregate (sum) the number of log lines for each level **across all three files**. 

Contents:
- `app1.log`: 3 INFO, 2 WARN, 4 ERROR
- `app2.log`: 9 INFO, 1 WARN, 5 ERROR
- `app3.log`: 10 INFO, 4 WARN, 4 ERROR

Totals: **INFO = 22, WARN = 7, ERROR = 13**.

Write the aggregated counts to `/app/summary.json`:

```json
{
  "INFO": 22,
  "WARN": 7,
  "ERROR": 13
}
```

Counts are exact integers; compute them from the files (e.g. `grep -c` or a Python counter), not by hand-estimating.