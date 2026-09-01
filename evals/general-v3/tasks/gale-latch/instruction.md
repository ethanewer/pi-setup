# Port the vendored Cython extension to numpy 2.x

`/app/src/gridops/` contains the working tree of a small vendored Cython
package, `gridops` (compiled module: `gridcore`). It was written years ago
against the numpy 1.x C API. The image you are on ships **numpy 2.x**, where
several legacy entry points were **removed**, so building it currently fails
outright. Your job is to port the package to numpy 2.x and hand back a
reusable, offline build script.

There is no network access at verify time; everything must build from the
local sources against the already-installed `numpy`, `Cython`, and
`setuptools`. The toolchain (`gcc`, `python3` headers) is already installed.

## What is broken

- `/app/src/gridops/setup.py` drives the build through
  `numpy.distutils`, which was **removed in numpy 2.0** — importing it raises
  `ModuleNotFoundError` and every build dies immediately.
- `/app/src/gridops/gridcore.pyx` calls the C-API function
  `PyArray_FromDims`, which was **removed from the numpy C API in 2.0**, so
  the generated C does not compile/link against the installed headers.

## Deliverables (all required)

1. **`/app/src/gridops/setup.py`** — a ported build configuration that does
   **not** use `numpy.distutils`. It must build the extension against the
   installed numpy using a modern configuration (`setuptools` plus
   `Cython.Build.cythonize`, with `numpy.get_include()` on the include path),
   and this must work:
   ```
   cd /app/src/gridops && python3 setup.py build_ext --inplace
   ```
2. **`/app/src/gridops/gridcore.pyx`** — the Cython source with the removed
   `PyArray_FromDims` call replaced by a supported allocation mechanism
   (e.g. `PyArray_SimpleNew`, or a plain `np.empty_like` / typed Cython
   buffer). The **numerical behavior must be preserved exactly** (see the
   contract below). You may keep `cimport numpy` and typed ndarray syntax.
3. **`/app/port.sh`** — a bash script (make it executable) that rebuilds the
   extension in place against the installed numpy and exits `0`:
   ```
   bash /app/port.sh
   ```
   It must be **idempotent** (safe to re-run on an already-built tree) and
   fully **offline** — no network access, no `pip install`, no downloading.
   After running it, this must work from any directory:
   ```
   PYTHONPATH=/app/src/gridops python3 -c "import gridcore"
   ```
   Do not bypass the package's build configuration: `port.sh` must build the
   sources through `/app/src/gridops/setup.py` (an independent grader will
   re-run that build command and expect it to succeed too).

## Behavior contract for `gridcore` (must hold after the port)

- `gridcore.rms(grid)` — `grid` is anything convertible to a contiguous 2-D
  float64 array. Returns the root-mean-square over **all** entries:
  `sqrt(mean(x**2))`. If the array has zero entries, returns `0.0`.
- `gridcore.scale(vec, factor)` — `vec` is anything convertible to a
  contiguous 1-D float64 array, `factor` a float. Returns a **new** 1-D
  float64 array with each entry `vec[i] * factor`. It must **not modify**
  the input array. An empty input yields an empty result array.

## Hidden / edge cases the grader will probe

The grader rebuilds via your `port.sh` and via the `setup.py` command above,
then exercises the compiled module on inputs you have not seen:

- `rms` on grids with negative entries, a single-entry grid, and a grid with
  zero entries (must return `0.0`);
- `scale` with zero and fractional factors, on an empty vector, and a check
  that the input array is left unmodified.

## Rules

- Do not change the public names or semantics of `rms` / `scale`.
- No network access; build only against what is installed in the image.
- Work only under `/app`.
