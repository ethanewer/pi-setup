/app/climate.json contains climate time-series metadata in the classic NetCDF/CF convention. It has two variables with these fields:

- `units`: an offset-based time unit such as `days since 1900-01-01 00:00:00` or `hours since 1980-01-01 00:00:00`
- `calendar`: the calendar used (here always `proleptic_gregorian` / `standard`, i.e. the usual leap-year rule: leap every 4 years except every 100 unless every 400)
- `offsets`: integer counts of the time unit elapsed since the reference date

Reading such data means converting the offsets into calendar dates: `date = ref_date + offset units`, with the leap-year rule applied on the way.

The JSON is:

```json
{
  "variables": [
    {"name": "daily", "units": "days since 1900-01-01 00:00:00", "calendar": "proleptic_gregorian", "offsets": [0, 1, 366, 4019, 39504, 39505, 39506]},
    {"name": "hourly", "units": "hours since 1980-01-01 00:00:00", "calendar": "standard", "offsets": [0, 24, 743, 744]}
  ]
}
```

Write `/app/convert.py` that parses `units` (split on `"since "`), converts every offset to an ISO date string `YYYY-MM-DD`, and writes `/app/dates.json`:

```json
[
  {"name": "daily", "dates": ["1900-01-01", ...]},
  {"name": "hourly", "dates": ["1980-01-01", ...]}
]
```

The order of `variables` entries must be preserved. Then run your script so `/app/dates.json` is produced. Use only the Python standard library (`datetime` module for date math).