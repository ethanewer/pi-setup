`legacy_vec` is a Cython extension package written for numpy 1.x / setuptools 40 /
Cython 0.2x. It was obsoleted by modern numpy & setuptools and no longer builds
(or runs) correctly.

Modules: `_core` (dot product, linspace, double-scalar) and `_filters`
(sliding-window sum).

Modernize so both build in place:

    python3 setup.py build_ext --inplace

Then iterate against the adversarial numeric evaluator:

    python3 tests/evaluate.py

Known problems to fix (validate by running the evaluator):
1. `setup.py` uses the removed `numpy.distutils`.
2. `_double_scalar` uses `np.float`, removed in numpy 1.24.
3. `window_sum` accumulates in single-precision `float`, producing large numeric
   errors on long/large-magnitude inputs (must be `double`).