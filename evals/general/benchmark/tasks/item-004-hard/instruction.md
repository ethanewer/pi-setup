In `/app/workbench` there is a legacy Python C-extension package `legacy_vec` written in 2016 for an older toolchain (numpy 1.x / setuptools 40 / Cython 0.2x). The container uses a modern toolchain (Python 3.12, numpy 2.x, Cython 3.x, current setuptools). The project does not build, and once built it does not pass a numeric accuracy evaluator.

Layout:

```
/app/workbench/
  setup.py
  legacy_vec/
    __init__.py
    _core.pyx
    _filters.pyx
  tests/
    evaluate.py     (runnable adversarial evaluator - DO NOT MODIFY)
  README.md
```

Public API (from `legacy_vec`):

- `_core` module:
  - `_dotprod(a, b) -> float`          1-D float64 dot product
  - `_linspace(low, high, n) -> array`  n evenly spaced float64 values
  - `_double_scalar(x) -> float`        2 * x  (currently uses removed `np.float`)
- `_filters` module:
  - `window_sum(a, w) -> array`  sliding-window sum: for each i, sum of `a[max(0,i-w) .. min(n,i+w+1))` (float64 out)

Your tasks, in order:

1. Make the package build in place. The current `setup.py` imports the removed `numpy.distutils`. Rewrite `setup.py` to use `setuptools` + `Cython.Build.cythonize` for **both** Cython sources. Add `numpy.get_include()` and the `legacy_vec/` dir to `include_dirs` for each. Then `python3 setup.py build_ext --inplace` from `/app/workbench`.

2. Fix the run-crash: `_double_scalar` uses the numpy alias `np.float` (removed in numpy 1.24). Patch `_core.pyx` minimally.

3. Fix a numerical (accuracy) bug in `_filters.pyx`: `window_sum` accumulates in a 32-bit `float` accumulator even though the reference computation and outputs are float64. On large-magnitude/long inputs this produces drift far above the evaluator's tolerance (1e-3). The correct implementation accumulates in `double`. Identify it and patch it.

4. Iterate against the supplied evaluator:

   ```
   python3 tests/evaluate.py
   ```

   It checks correctness on several inputs, at least one of which is long/large-magnitude (adversarial) and only passes when the accumulator is float64. It prints a per-case result. Goal: every check passes (`PASS` lines printed, process exits 0).

Constraints:

- Do not modify anything under `tests/`.
- Do not add third-party packages. numpy, cython, setuptools, and the C compiler are already installed.
- The extension must build and import from `/app/workbench` (in-place build).
- Final state: `python3 setup.py build_ext --inplace` succeeds and `python3 tests/evaluate.py` reports all-PASS / exits 0.