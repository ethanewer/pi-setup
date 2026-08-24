# Million-row processing

`/app/data/measurements.txt` contains **1,000,000** lines. Each line is a weather measurement:

```
station_name;temperature
```

- `station_name` is a string like `st03` (there are exactly 40 stations, named `st00` through `st39`).
- `temperature` is a decimal number that may be negative, e.g. `-3.2`, `-12.7`, or `38.1`, always with exactly one decimal place.

Compute, **per station** (aggregating over all its measurement lines):

- the **minimum** recorded temperature,
- the **maximum** recorded temperature,
- the **arithmetic mean** temperature (sum / count).

Write the results to `/app/results.txt`, one line per station, **sorted alphabetically by station name**, with the format:

```
st00;min;max;mean
```

For each station, values are rounded (min and max) to the recorded one-decimal precision, and the mean to **one decimal place** via Python's `round(mean, 1)`. Example line: `st03;-17.9;39.4;8.3`.

Use an efficient streaming approach (do **not** accumulate all 1,000,000 lines in memory at once — accumulate per-station running sums/counts/mins/maxs in a single pass). A simple `dict` keyed by station name is sufficient and fast.

Your `/app/results.txt` must contain exactly 40 lines, one per station, in alphabetical order, matching the aggregated statistics computed by an independent re-scan of the same input file.