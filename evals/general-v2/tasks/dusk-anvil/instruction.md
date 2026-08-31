# Port the hexcore Cython extension to the numpy 2.x C API

`/app/hexcore` is the vendored source tree of **hexcore**, an internally-built
Cython extension used by the mapping stack. The build machine has been
upgraded to **numpy 2.x** (this is the numpy that is installed and that must
stay installed), and the extension no longer builds against it because parts
of the tree still use the legacy numpy C API that numpy 2.0 removed.

Your job: repair the source tree in place so that it builds, installs, and
passes its test suite against the installed numpy 2.x, and leave the built
package installed for the system `python3`.

## Environment

- Working directory: `/app`. The source tree lives at `/app/hexcore`.
- Toolchain present: `gcc`, `python3` (3.12), `pip`, `setuptools`, `cython`,
  `numpy` 2.x, `pytest`. No network access is needed or available.
- The tree layout:
  - `/app/hexcore/setup.py` — modern `setuptools` + `Cython.Build.cythonize`
    build configuration (already correct; you should not need to change it).
  - `/app/hexcore/hexcore/_engine.pyx` — Cython glue exposed as `hexcore`.
  - `/app/hexcore/hexcore/_arrays.c` / `_arrays.h` — hand-written C engine
    compiled into the same extension.
  - `/app/hexcore/tests/test_hexcore.py` — the target test suite.

## What is broken

1. **`_arrays.c` uses the removed `NPY_ARRAY_UPDATEIFCOPY` flag.** The
   `clamp_inplace` fast path needs a contiguous temporary whose contents are
   written back into a (possibly non-contiguous) view. The legacy code
   attaches the temporary with `NPY_ARRAY_UPDATEIFCOPY`, which was deprecated
   in numpy 1.14 and **removed in numpy 2.0** — compiling fails with
   `NPY_ARRAY_UPDATEIFCOPY undeclared`. Port this mechanism to the modern
   numpy 2.x API (e.g. the `NPY_ARRAY_WRITEBACKIFCOPY` machinery with an
   explicit resolve, or an equivalent explicit owner/commit scheme) so the
   observed behavior is unchanged.
2. **`_engine.pyx` uses Python-level aliases removed in numpy 2.0** —
   `np.Inf` (in the `DEFAULT_LO`/`DEFAULT_HI` clamp defaults) and `np.float_`
   (in `as_floats`). Even after a successful build the module would crash on
   import. Replace them with the supported equivalents.

## Required behavior (the grader re-checks all of this on inputs you have not seen)

- `hexcore.zoom(a)` — new float64 ndarray, `2.0 * a` elementwise, any shape.
- `hexcore.mirror(a)` — new float64 ndarray, elements in reversed flat order,
  same shape as `a`.
- `hexcore.total(a)` — sum of all elements as a Python float (`0.0` for
  empty input).
- `hexcore.as_floats(obj)` — `obj` (sequence or scalar, numeric strings
  included) converted to a float64 ndarray.
- `hexcore.clamp_inplace(a, lo, hi)` — clamps every element of the float64
  ndarray `a` into `[lo, hi]` **in place**. Defaults `lo`/`hi` are
  `-inf`/`+inf`. Must work for **any writable float64 array, including
  non-contiguous views** (transposes, sliced views, Fortran-ordered arrays):
  writes made through a view must be visible in the underlying base array.
  Raises `TypeError` for non-ndarray input or a non-float64 dtype and
  `ValueError` for a read-only array.
- `import hexcore` must work in a fresh interpreter with the system
  `python3` and `numpy.__version__` starting with `2.`.

## Deliverables (all required)

The grader treats these three files of the repaired tree as the deliverables
and re-builds and re-installs the package **from your tree**:

1. `/app/hexcore/setup.py` — the build configuration (must still work with
   `python3 -m pip install --no-build-isolation --no-deps /app/hexcore`).
2. `/app/hexcore/hexcore/_engine.pyx` — repaired Cython glue.
3. `/app/hexcore/hexcore/_arrays.c` — repaired C engine.

You must also:
- run `python3 -m pip install --no-build-isolation --no-deps /app/hexcore`
  so the repaired extension is installed for the system `python3`;
- make `python3 -m pytest -q /app/hexcore/tests` pass.

## Rules

- Do **not** reference the removed flag `NPY_ARRAY_UPDATEIFCOPY` anywhere in
  the tree — no compat `#define` shims; use the modern API or an explicit
  scheme.
- Do not downgrade or pin numpy; the grader verifies numpy 2.x is active.
- Do not modify or weaken `/app/hexcore/tests/test_hexcore.py` (the grader
  detects tampering), and do not delete build outputs you need.
- You may add new files to the tree if your port needs them, and you may
  edit `_arrays.h` to match a changed C interface.
- The grader runs the probe battery on hidden inputs, so the repairs must be
  general, not special-cased to the visible tests.
