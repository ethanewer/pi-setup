# Author the `dotkit` package exposing `dot` from its root module

A telemetry vendor ships an on-device scalar-product utility. Your job is to
**author a small installable Python package from scratch** in `/app/pkg` (the
directory exists but is empty apart from a `.gitkeep`). Python 3.12 and
`python3 -m pip` (offline-capable with `--no-build-isolation`) are available;
there is no network access.

## Required package structure

```
/app/pkg/
  pyproject.toml
  dotkit/
    __init__.py
    core.py
```

1. `/app/pkg/pyproject.toml` — a valid PEP 517 project using the setuptools
   build backend (`build-backend = "setuptools.build_meta"` with a
   `[build-system]` that requires `setuptools`), with:

   - `name = "dotkit"`
   - `version = "1.3.0"`
   - package discovery that picks up the **flat-layout** package `dotkit`
     (an explicit `[tool.setuptools] packages = ["dotkit"]` table is the
     robust way to do this).

2. `/app/pkg/dotkit/core.py` — the numeric kernel. It must define:

   ```python
   def dot(a, b):
   ```

   `dot` computes the **scalar (dot) product** of two numeric sequences:

   - `a` and `b` are sequences of numbers (ints and/or floats) of equal
     length — lists or tuples.
   - It returns the sum of the elementwise products, e.g.
     `dot([1, 2, 3], [4, 5, 6])` -> `32`.
   - **Empty sequences** return `0` (there are no terms).
   - If the two sequences have **different lengths**, it must raise
     `ValueError`.
   - It must not print anything or mutate its inputs.

3. `/app/pkg/dotkit/__init__.py` — the **entry (root) module**. It must
   re-export the kernel so **all** of these work on the installed package:

   ```python
   import dotkit
   dotkit.dot(a, b)          # exposed from the root module

   from dotkit import dot    # importable by name from the root module

   import dotkit.core
   dotkit.core.dot(a, b)     # kernel importable from its own submodule
   ```

   `from .core import dot` plus `__all__ = ["dot"]` is the intended shape;
   any arrangement satisfying the three access paths above is fine.

## How it is graded

The verifier **installs `/app/pkg` offline** (roughly
`python3 -m pip install --no-index --no-deps --no-build-isolation --target <dir> /app/pkg`)
into a scratch directory and then imports the *installed* package. If the
package layout, metadata, or import paths are wrong — or `dot` is missing,
misnamed, or not reachable from the root module — the install or the import
checks fail. The same checks run on the visible case below and on several
hidden inputs (ints, floats, negatives, tuples, empty sequences, and a
length-mismatch `ValueError` case), so implement the general contract, not a
hard-coded answer.

Sanity check you can run locally:

```bash
python3 -m pip install --quiet --no-index --no-deps --no-build-isolation \
    --target /tmp/dk_check /app/pkg
PYTHONPATH=/tmp/dk_check python3 -c "import dotkit; print(dotkit.dot([1,2,3],[4,5,6]))"
# must print 32
```

## Constraints

- No network access; standard library only (no third-party runtime
  dependencies in the built metadata).
- Keep everything inside `/app/pkg`; do not add build artifacts elsewhere.
