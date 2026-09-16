# Notes on building and testing this tree

The repository at `/app/src` is a real upstream project (SciPy) checked out
at a pinned, shallow (single) commit. Everything needed to build and test it
offline is baked into this image:

- A complete build toolchain (`build-essential`, `gfortran`, `pkg-config`,
  `ninja-build`, meson, meson-python, Cython, pybind11, pythran), the OpenBLAS
  BLAS/LAPACK implementation (`libopenblas-dev`), and the runtime dependency
  `numpy`, all pip-pinned, plus `pytest`.
- SciPy itself, compiled from this source tree and installed in **editable**
  mode from `/app/src` (`pip install --no-build-isolation -e .`). The C/C++/
  Fortran extension modules were built at image build time; any edit you make
  to a plain `.py` file under `/app/src/scipy` is live for the next
  `import scipy` without any rebuild or reinstall step.
- `python3 -m pytest` from `/app/src` runs the project's own test suite
  (its pytest configuration lives in `/app/src/pytest.ini`).

Common commands (all offline):

    cd /app/src
    python3 -m pytest scipy/optimize/tests/test_optimize.py::test_bounds_with_list -q
    python3 - <<'EOF'
    import scipy
    print(scipy.__version__, scipy.__file__)
    EOF

SciPy's pytest configuration turns warnings into errors, so run only targeted
test node ids.

Do not modify the `.git` directory (its history is intentionally shallow),
and do not commit, fetch or pull.