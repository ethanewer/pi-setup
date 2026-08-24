# Item-056 (hard) — native C extension for portfolio risk/return

`/app/prices.csv` contains daily closing prices for **8 assets** (`p0`..`p7`), one
column per asset, 122 rows (121 daily intervals), comma-separated with a header row.

Your goal is to write a **Python C extension** named `fastport` (a compiled native
module built with `setuptools` from a `fast_port.c` source file) that computes a
small mean-variance portfolio contraction in a tight C loop, verify it matches a
pure-NumPy reference, and benchmark the two.

## Compute the portfolio statistics from prices.csv

1. Daily returns: `R[t] = P[t+1] / P[t] - 1` per asset.
2. Mean-return vector: `mu = R.mean(axis=0)` (length-8).
3. Covariance matrix: `cov = numpy.cov(R, rowvar=False)` (8x8).
4. Use equal weights `w = full ones / 8`.

Define:
- `expected_return = w @ mu`
- `portfolio_variance = w @ (cov @ w)`

## The C extension

Write `/app/src/fast_port.c` — a standard CPython extension module exposing

```
fastport.compute(w, mu, cov) -> (expected_return, portfolio_variance)
```

- `w`, `mu` are 1-D contiguous float64 arrays; `cov` is a 2-D C-contiguous float64
  array.
- Read them with the **Python buffer protocol** (`PyObject_GetBuffer` /
  `PyBuffer_Release`) so NumPy arrays are consumed without conversion.
- Implement the two contractions in plain C `for` loops (do not call back into
  Python).
- Validate the shapes (w and mu length 8; cov 8x8) and raise `ValueError` on
  any mismatch.

Write `/app/src/setup.py` that builds the module from `fast_PORT.c` with
`setuptools.Extension`, and build it in place (`build_ext --inplace`) so
`import fastport` works.

## Deliverables

- `/app/src/fast_port.c` and `/app/src/setup.py` (the C source + build script).
- The compiled native `.so` module (make `import fastport` succeed from `/app`).
- `/app/result.json`: `{"expected_return": ..., "portfolio_variance": ...,
  "n_assets": 8}`.
- `/app/benchmark.json`: your measured timing, e.g.
  `{"c_seconds_per_call": ..., "numpy_seconds_per_call": ..., "speedup": ...,
  "calls": ...}`.
- `/app/weights.json`: the exact weights array used (`[0.125, 0.125, ... ]`).

## Verification

The verifier will:
- build the extension is present (a compiled `.so`),
- recompute `mu`, `cov` from `prices.csv` and the equal weights, and require
  your `result.json` values to match the NumPy reference within `1e-9` (after
  round-off),
- require `benchmark.json` to exist with a measured (positive) `speedup`.

Match your native result to the NumPy reference exactly. Keep the C loop tight; the
verifier checks values, not absolute speed, but your `benchmark.json` must report a
real measurement.