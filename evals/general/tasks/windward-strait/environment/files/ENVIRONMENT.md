# Environment notes for the SciPy trust-region debugging task

`/app/src` is a working tree of the SciPy project (Python 3.12) built from
source and installed in **editable/dev mode**, so `import scipy` resolves
straight into `/app/src` and edits to the library source take effect on the
next process start. **No rebuild is needed after a pure-Python edit.**

Convenient commands (run from `/app/src`):

    python3 -c "import scipy; print(scipy.__file__)"
    python3 -m pytest -q scipy/optimize/tests/test_trustregion.py -p no:cacheprovider

The tree is a shallow single-commit git checkout at the buggy revision; there
is no history to consult. `git status` and `git diff` work in the usual way.

The image is an on-site source build: everything the trust-region code path
needs is present (numpy, scipy.linalg, scipy.optimize, pytest); some unrelated
compiled back-ends are not linked, so stick to the trust-region solvers for
your checks and do not attempt to fetch or install anything.