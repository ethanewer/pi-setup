In `/app` there is a CSV file `models.csv` with a header row and columns:

- `model` — model name
- `params_m` — parameter count in millions
- `accuracy_pct` — evaluation accuracy in percent (higher is better), increasing with size

The rows are already sorted by increasing `params_m`. Write a Python script `/app/analyze.py` that reads the CSV and computes:

1. `small_to_large_delta`: accuracy of the largest model minus accuracy of the smallest model.
2. Consecutive accuracy gains: for each adjacent pair `(i, i+1)` in the sorted list, `gain = acc[i+1] - acc[i]`. Find the pair with the **largest gain**. If there is a unique largest gain, `max_gain_row = "<name_i>-><name_{i+1}>"`; `max_gain_value` = that gain (rounded to 2 decimals). If ties, pick the first adjacent pair that achieves the maximum.
3. `best_model` = the name of the model with the highest `accuracy_pct`; `best_acc` = its accuracy.

Write `/app/analysis.json` as exactly:
```json
{"best_model": "<name>", "best_acc": <float>, "max_gain_row": "<a>-><b>", "max_gain_value": <float>, "small_to_large_delta": <float>}
```

Use `params_m` only to confirm the ordering is increasing; base all computations on `accuracy_pct`. The standard library `csv` module is sufficient.

Run the script so `/app/analysis.json` exists with the correct values.