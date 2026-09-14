# clew-bulkhead build notes

- SciPy is checked out at a pinned historical commit in `/app/src` (detached
  HEAD, clean tree) and warm-built **editably** from that tree: pure-Python
  files are served from `/app/src`, compiled modules from
  `/work/sci-build` (the meson build dir).
- Rebuild after a source edit:

  ```
  cd /app/src && python3 -m pip install -e . --no-build-isolation \
      --config-settings=builddir=/work/sci-build
  ```

  Incremental; at 1 CPU a single changed Cython module takes seconds.
- Import/pytest must run from **outside** `/app/src` (SciPy refuses to
  import from inside its source directory):

  ```
  cd /tmp && python3 -m pytest /app/src/scipy/spatial/tests/test_qhull.py
  ```

- No network; pip is locked to the local index (`PIP_NO_INDEX=1`). Build
  toolchain (cython/meson/ninja/meson-python/pybind11/pythran) and OpenBLAS
  are installed and pinned.