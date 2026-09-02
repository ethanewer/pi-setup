# SciPy / pandas analysis

`/app/sensors.csv` is a CSV with header `sensor_id,time_ms,value`. It contains deterministic synthetic sensor readings for three sensors (`sensor_id` 1, 2, 3): each sensor has 100 readings, one every 25 ms, in increasing `time_ms` order.

Write a Python program at `/app/analyze.py` that uses **pandas** and **SciPy** to produce `/app/results.json`.

## Steps

1. Load the CSV with `pandas.read_csv('/app/sensors.csv')`.
2. Group by `sensor_id`. For **every** sensor present (1, 2, and 3), sort its rows by `time_ms` ascending and compute:
   - `mean` — the mean of its `value` column, rounded to 2 decimal places (`round(x, 2)`),
   - `median` — the median of its `value` column, rounded to 2 decimal places,
   - `peak_count` — the number of peaks found by
     ```python
     from scipy.signal import find_peaks
     peaks, _ = find_peaks(values, prominence=10, distance=3)
     peak_count = len(peaks)
     ```
     where `values` is the sensor's `value` column as a NumPy array, in `time_ms` order.

## Output format

Write `/app/results.json`:

```json
{
  "per_sensor": [
    {"sensor_id": 1, "mean": 22.8, "median": 24.73, "peak_count": 2}
  ]
}
```

with one entry per sensor, in ascending `sensor_id` order. `mean` and `median` are floats rounded to 2 decimals; `peak_count` is an integer.

Do not modify `sensors.csv`. Run the program so the JSON file exists at the end.