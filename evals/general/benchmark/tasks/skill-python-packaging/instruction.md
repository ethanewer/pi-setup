# Python package authoring

Structure a small, importable Python package in `/app` and use it from a driver script.

Requirements:

1. Create a package directory `/app/mypkg/` containing `__init__.py`. In `__init__.py`, define a function `classify(n)` that returns:
   - `"negative"` if `n < 0`
   - `"zero"` if `n == 0`
   - otherwise `"positive"`
2. As part of the package (good packaging practice), you may add any supporting modules under `/app/mypkg/` if helpful, but `__init__.py` must be a valid module exposing `classify`.
3. Write `/app/driver.py` that makes `/app` importable (so `from mypkg import classify` works when the driver runs with CWD `/app`), reads each integer from `/app/input.txt` (one per line), and writes to `/app/results.txt` one `classify` result per line in the same order.

Run `/app/driver.py` so `/app/results.txt` is produced. The package must be importable as `mypkg` and `mypkg.classify` must work for any integer input.
