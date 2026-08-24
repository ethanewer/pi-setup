At `/app/dates.txt` each line has the form:

```
<YYYY-MM-DD> <integer-days>
```

Write `/app/add_days.py` that:
1. reads `/app/dates.txt`,
2. parses each date and integer, and adds that many days to the date (respecting calendar month lengths and **leap years**; negative day counts subtract),
3. writes the resulting ISO-8601 date (`YYYY-MM-DD`) for each input line, one per line, to `/app/results_out.txt`.

The output line order must match the input line order, and dates must be zero-padded (e.g. `2024-09-13`). Use only the Python standard library (`datetime`). Run the script so `/app/results_out.txt` exists.

The verifier recomputes the expected dates itself from `/app/dates.txt` and compares them to `/app/results_out.txt`.
