# Build a fast C extension and benchmark it against a pure-Python reference

## Context

`/app` contains a portfolio risk/return micro-benchmark:

- `/app/native.c` — a **C extension** (Python C API) exposing `native.eval(mu,
  cov_flat, w, N)` which computes `ret = sum(w_i * mu_i)` and
  `var = sum_i w_i * (sum_j cov_ij*w_j)` in C.
- `/app/setup.py` — a setuptools build script that compiles `native.c` into an
  importable module named `native`.
- `/app/port_math.py` — `stats_reference(w, mu, cov)`, a **pure-Python/NumPy
  reference** version of the same computation.
- `/app/run_bench.py` — a benchmark harness that exercises the fast extension
  and the reference on the **same fixed inputs**, checks the results match,
  and measures each implementation's wall-clock time.
- `/app/mu.txt`, `/app/cov.txt`, `/app/w.txt` — fixed inputs (a return vector,
  a covariance matrix, and a weight vector).

Preserve the reference implementation as-is. Your job collapses to: **build the
C extension**, verify the fast path reproduces the reference exactly, measure
speed/correctness separately, and write a machine-readable result.

## Steps

1. **Build the extension** so `import native` works in `/app`:
   `python3 setup.py build_ext --inplace` (or `pip install .`). The compiled
   module will appear in `/app`.
2. **Optimize check**: don't touch `port_math.py`. Run the benchmark:
   `python3 run_bench.py`. It imports `native` and `stats_reference`, checks
   `match` (both ret and var agree within 1e-6 relative), times each, and
   writes `/app/out/report.json`.

   If the fast path does **not** match the reference, investigate `native.c`
   and fix it (e.g. a wrong index in the matvec) before proceeding. The
   extension must be *correct* before you trust its speed measurement.

3. **Confirm the report** `/app/out/report.json` exists with:
   ```json
   { "ref_ret": <float>, "ref_var": <float>,
     "fast_ret": <float>, "fast_var": <float>,
     "match": true,
     "ref_sec": <float>, "fast_sec": <float>,
     "speedup": <float> }
   ```
   `match` must be `true`.

## Success criteria

- The `native` module is importable (compiled C extension present).
- `match` is `true`: the C path numerically reproduces the pure-Python reference
  for `ret` and `var` (within 1e-6 relative).
- `fast_ret`/`fast_var` equal the reference values to that tolerance **and**
  match an independent re-computation of the same inputs.

Note: you may not modify `run_bench.py` or `port_math.py`; only the extension
build (and `native.c` if you must fix a bug).