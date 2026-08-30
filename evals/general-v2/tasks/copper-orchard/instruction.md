# Summarize a noisy experiment ledger

`/app/readings.csv` is a deliberately messy CSV export from a lab instrument.
It records one or more `reading` values for each experiment `device`. Build a
small, reusable Python program that turns any such CSV (with the same contract
below) into a compact JSON statistical summary, and use it to summarize the
provided file.

## Deliverables

Write exactly two artifacts under `/app`:

1. **`/app/solve.py`** — a runnable Python 3 program. It must parse a CSV
   according to the contract below and be *general*, i.e. work correctly on any
   input matching that contract (the verifier will run it on other CSVs it
   provides, not just the shipped one). Command-line contract:

   ```
   python3 /app/solve.py [INPUT.csv [OUTPUT.json]]
   ```
   Default input is `/app/readings.csv`; default output is `/app/answer.json`.

2. **`/app/answer.json`** — the JSON summary your program produces for
   `/app/readings.csv` (run your `solve.py` yourself to generate it).

## Input contract (must hold exactly)

- CSV rows are separated into named columns via a header line.
- The two columns you care about are named `device` and `reading`.
  Matching is **by header name**, not by column position: the `device` and
  `reading` columns may appear in any order, extra unrelated columns may exist,
  and header labels may contain leading/trailing whitespace (e.g. `" device "`),
  which you must strip before matching.
- A `reading` cell is a *valid numeric reading* iff it is a real number
  (integers or decimals, including negatives). Blank cells, whitespace-only
  cells, and non-numeric text (e.g. `n/a`, `zzz`) are **invalid and skipped**.
- A row is ignored entirely if its `device` name is empty/whitespace.
- Trailing blank or malformed lines must not cause an error; they are skipped.

## Summary computation (exact)

For every device, use only its valid numeric readings.

1. **`devices`**: median of that device's valid readings, where the median is
   the middle value when the count is odd, and the average of the two middle
   values when it is even. A device with a single reading has that reading as
   its median.

2. **`trimmed_mean`**: for each device, discard its single lowest and single
   highest reading (when it has at least 3 valid readings), then pool all the
   surviving readings across devices and take the mean. Devices with fewer than
   3 valid readings contribute **all** of their readings to the pool (nothing is
   discarded). If the pool ends up empty, `trimmed_mean` is `null`.

3. **`bootstrap90`**: a 90% bootstrap (empirical) confidence interval for the
   mean of the pooled trimmed readings used in step 2. Do this with a fixed
   `random.Random(SEED)` seeded with **42**, **2000** resamples with
   replacement, and report the 5th and 95th percentiles of the resampled means
   (linear interpolation between adjacent sorted values for percentile ranks).
   Fixed seed ⇒ deterministic result. If the pool is empty, `bootstrap90` is
   `null`.

## Output format (exact)

`/app/answer.json` must be JSON with exactly these keys, in this order:

```
{
  "devices": { "<device_name>": <median>, ... },
  "trimmed_mean": <number or null>,
  "bootstrap90": [<lo>, <hi>] or null
}
```

- Device names are sorted **alphabetically**.
- Numeric values are plain JSON numbers; `null` is written only as in the
  rules above (never quote it).

## Edge cases the hidden checks probe

Make sure your program handles all of the following (the verifier's extra
inputs cover this range):

- `device`/`reading` columns in reversed or shuffled order and extra columns.
- Header labels padded with spaces.
- Blank, whitespace-only, and non-numeric `reading` cells (skipped, no crash).
- Negative and very large / extreme numeric readings (an extreme value must be
  dropped by the per-device trim, not corrupt the result).
- A device with exactly one valid reading.
- A device with exactly two valid readings (both go through into the pool).
- An input whose rows contain **no valid numeric readings at all** — the
  program must still exit 0 and emit `devices: {}`, `trimmed_mean: null`,
  `bootstrap90: null`.

## Rules

- Do **not** modify or delete `/app/readings.csv`, and make no other changes to
  the device other than creating the two deliverables.
- The program must read its input from the path given on the command line (or
  the default) and write JSON to the requested output path. It must not assume
  bytes from this specific file beyond the documented contract.
- Output must be deterministic and require **no network access**.