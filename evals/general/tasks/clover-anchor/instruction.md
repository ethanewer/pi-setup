# Fit the greenhouse centroid model and pickle it

Clover-Anchors' horticulture team logs sensor readings for its grow plots and
wants a tiny "nearest-centroid" model fitted from the readings, persisted to a
pickle file that any later process can reload offline (there is **no network
access** in this environment).

## Files provided (do NOT modify them)

- `/app/data/zone_readings.csv` — comma-separated readings with a header line:
  `plot_id,temp_c,humidity_pct,light_lux,zone`

  The first column `plot_id` is a row identifier and is **not** a feature.
  Columns `temp_c`, `humidity_pct`, `light_lux` (in this order) are the three
  numeric features; the last column `zone` is the class label (a short string).
  `python3` is available; nothing else is needed.

## Deliverable 1 — `/app/fit.py`

A runnable Python program with EXACTLY two positional arguments:

```
python3 /app/fit.py <input_csv> <output_pkl>
```

It reads the CSV (the path is given on the command line, not hard-coded), fits
a nearest-centroid model, and `pickle.dump`s a single dict to the output path.
The pickle file must be non-empty and loadable with `pickle.load`.

The fitted dict must have **exactly** these keys:

```python
{
  "model": "nearest-centroid",
  "fitted": True,
  "n_features": <int, always 3 for this schema>,
  "n_samples": <int, number of data rows>,
  "classes": [<class labels, sorted ascending as strings>],
  "centroids": {<class label>: [<mean temp_c>, <mean humidity_pct>, <mean light_lux>]},
}
```

Fitting rules:

- For each distinct `zone`, the centroid is the **arithmetic mean** of each
  numeric feature over all rows of that zone (sum divided by count; plain
  Python floats — do not round).
- `classes` lists every distinct zone label sorted ascending (standard string
  sort), which is also exactly the key set of `centroids`.
- Rows may appear in any order; row order must not change the fitted dict.
- The CSV always has a header line; data rows follow it. Ignore nothing else:
  every data row has a non-empty zone and three parseable floats.

## Deliverable 2 — `/app/model.pkl`

The pickle produced by running your program on the provided data:

```
python3 /app/fit.py /app/data/zone_readings.csv /app/model.pkl
```

## Constraints

- Pure Python 3 / standard library only. Deterministic; no network.
- The verifier loads your pickles with `pickle.load` and checks the exact key
  set, the `classes` list, and every centroid value against an independently
  computed reference (small float tolerance).
- It also runs `/app/fit.py` unchanged on hidden CSVs conforming to the same
  schema (different zones, a single class, negative values) and inspects the
  resulting pickles the same way.
- Do not modify or move anything under `/app/data`.

## What to deliver

1. `/app/fit.py` — the fitting program described above.
2. `/app/model.pkl` — the pickle for the provided `/app/data/zone_readings.csv`.
