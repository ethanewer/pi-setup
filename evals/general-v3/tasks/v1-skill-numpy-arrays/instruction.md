# NumPy array manipulation

`/app/scores.txt` contains **50 integers**, one per line (non-negative, < 25).

Write a Python script `/app/stats.py` that uses **NumPy arrays** (in particular
**boolean masking**, **fancy indexing** via `np.where`, and array aggregations such as
`max` / `mean`) to compute the following statistics:

1. `count_gt15` — how many elements are **greater than 15**
2. `idx_div3` — the 1-D integer array of **indices** of all elements divisible by **3**
   (indexing from 0; use `np.where` / `np.nonzero`)
3. `mean_gt10` — the **mean** of all elements **greater than 10** (if none, use 0.0),
   rounded to 2 decimal places
4. `max_val` — the maximum element

Write the results to `/app/stats.json` as a JSON object with exactly these keys:

```json
{"count_gt15": 13, "idx_div3": [2, 5, ...], "mean_gt10": 17.42, "max_val": 24}
```

Note: `idx_div3` must be serialized as a regular JSON list of integers (call
`.tolist()` on the numpy array). Run your script so `/app/stats.json` exists. The
verifier recomputes every statistic from the same file with NumPy and compares.