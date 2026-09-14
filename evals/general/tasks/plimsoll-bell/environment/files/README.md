# Working checkout: scipy (development tree, built from source)

- The scipy source tree is at **`/app/src`**, checked out detached at the
  exact revision this task was measured against (the bug is present there).
  It was built from source (meson) and installed **editably** — a
  PEP 660 "redirect" editable install. Imports of `scipy` resolve pure-Python
  modules straight from the checkout, so **edits you make under `/app/src`
  take effect immediately — no rebuild, no reinstall**:

  ```bash
  cd /app/src && python3 -c "import scipy; print(scipy.__file__)"
  # /app/src/scipy/__init__.py
  ```

  Compiled extension modules are loaded from the meson build directory that
  was created when the image was built; you never need to touch or rebuild
  them. The build toolchain (meson, ninja, a C/C++/Fortran compiler) is all
  present, but a rebuild is neither required nor recommended: the fixed tree
  is pure Python.

- The container has **no network**. Do not try to `pip install`, `git fetch`,
  or download anything; every dependency the project's test suite needs is
  already installed (numpy, pytest, hypothesis, pooch, mpmath).

- Running the project's own tests, e.g. the one-sample KS slice:

  ```bash
  cd /app/src && python3 -m pytest -q -o addopts= -o filterwarnings=ignore \
      -p no:cacheprovider scipy/stats/tests/test_stats.py -k "TestKSTest or TestKSOneSample"
  ```

  Focused runs take seconds. Keep scratch files under `/tmp`, never inside
  the repository.

- The checkout is a git repository at the pinned revision with a clean tree.
  `git status`, `git log`, `git diff` and `git grep` are yours to use; never
  move the checked-out revision and never `git commit`.