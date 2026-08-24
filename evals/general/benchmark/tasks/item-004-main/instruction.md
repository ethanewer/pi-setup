In `/app/workbench` there is a legacy Python extension package called `legacy_vec`. It was written in 2016 for an older toolchain (Python 3.6 / numpy 1.1x / setuptools ~45 / Cython 0.2x). The installed toolchain in this container is modern (Python 3.12, numpy 2.x, Cython 3.x, current setuptools), and the project no longer builds or runs. Your job is to modernize it so that it compiles in place and passes its smoke suite.

Layout:

```
/app/workbench/
  setup.py
  legacy_vec/
    __init__.py
    _core.pyx
  tests/
    smoke.py      (runnable evaluator - DO NOT MODIFY)
  README.md
```

The package exposes three C-extension functions (defined in `legacy_vec/_core.pyx`):

- `_dotprod(a, b)` - manual dot product of two 1-D float64 numpy arrays.
- `_linspace(low, high, n)` - returns n evenly spaced float64 values in `[low, high]`.
- `_double_scalar(x)` - returns `2 * x`.

Work sequence:

1. Run `python3 setup.py build_ext --inplace` from `/app/workbench`. The build currently fails: `setup.py` imports from `numpy.distutils`, which was removed/obsoleted in modern numpy. Rewrite `setup.py` to use `setuptools` + `Cython.Build.cythonize`, and include `numpy.get_include()` plus the `legacy_vec/` source directory in `include_dirs`. Then re-run the build.

2. After the extension builds, run the supplied evaluator:

   ```
   python3 tests/smoke.py
   ```

   It will report which checks pass. Currently `_double_scalar` is broken at runtime: the `.pyx` uses the numpy alias `np.float`, which was removed in numpy 1.24. Patch `legacy_vec/_core.pyx` minimally so that it no longer references removed numpy aliases. You may also modernize the (deprecated) buffer-typed signatures if you wish, e.g. to typed memoryviews, but that is optional.

3. Iterate: rebuild with `python3 setup.py build_ext --inplace`, rerun `python3 tests/smoke.py`, until it exits 0 with no failures.

Requirements and constraints:

- `tests/smoke.py` must remain unchanged; do not edit test files.
- Do not add new third-party packages. Everything needed (numpy, cython, setuptools, a C compiler) is already installed.
- The extension must build and import from `/app/workbench` (i.e. a compiled `legacy_vec._core` extension must be importable there). Build in place with `build_ext --inplace`.
- Final state: `python3 setup.py build_ext --inplace` succeeds, and `python3 tests/smoke.py` exits 0 (prints `smoke fails: 0`).