# timezone / date ranges

`/app/events.json` is a JSON array of UTC timestamps in ISO-8601 format, e.g.
`"2024-06-02T02:00:00Z"`.

Write a Python program at `/app/analyze.py` that reads the array and computes, for
each of the two timezones `America/New_York` and `Asia/Tokyo`, the **local calendar
date** each timestamp lands on (using IANA timezone data, e.g. `zoneinfo.ZoneInfo`).

For each timezone compute:
- `min_date` — the earliest local calendar date seen, as `YYYY-MM-DD`,
- `max_date` — the latest local calendar date seen,
- `counts` — a list of `{"date": ..., "count": ...}` objects, one per distinct local
  date **for that timezone**, sorted ascending by date.

Write the result to `/app/ranges.json`:

```json
{
  "America/New_York": {
    "min_date": "2024-06-01",
    "max_date": "2024-06-03",
    "counts": [
      {"date": "2024-06-01", "count": 3},
      {"date": "2024-06-02", "count": 3},
      {"date": "2024-06-03", "count": 2}
    ]
  },
  "Asia/Tokyo": {
    "min_date": "2024-06-02",
    "max_date": "2024-06-04",
    "counts": [
      {"date": "2024-06-02", "count": 4},
      {"date": "2024-06-03", "count": 3},
      {"date": "2024-06-04", "count": 1}
    ]
  }
}
```

Treat every timestamp as UTC. Do not modify `events.json`. Produce `/app/ranges.json`.