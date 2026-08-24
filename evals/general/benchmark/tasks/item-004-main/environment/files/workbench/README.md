`legacy_vec` is a small Cython extension package originally written against
numpy 1.x / setuptools 40 / Cython 0.2x.

Public functions (all in the compiled module `legacy_vec._core`):

* `_dotprod(a, b) -> float`            manual 1-D float64 dot product
* `_linspace(low, high, n) -> arr`      n evenly spaced values in [low, high]
* `_double_scalar(x) -> float`          2 * x

Build in place with:

    python3 setup.py build_ext --inplace

Evaluate with:

    python3 tests/smoke.py

It currently does not build (setup.py depends on the removed `numpy.distutils`) and,
once built, `_double_scalar` crashes because the source uses the numpy alias `np.float`
removed in numpy 1.24. Modernize the packaging and the extension so both are fixed.