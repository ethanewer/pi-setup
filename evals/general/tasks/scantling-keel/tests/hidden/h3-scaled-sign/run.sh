#!/bin/bash
# Hidden case h3: the sign equation carries a coefficient, 2*sign(x)-2=0,
# again paired with x*y-4. The upstream regression test never scales the
# sign; this exercises the same code path from an input it does not use. On
# the pre-fix tree the call crashes with a raw TypeError; after the fix it
# must raise a clear solver-level NotImplementedError naming the solution
# type ('Interval').
set -u
cd /app/src || exit 1
SYMPY_SRC=/app/src python3 /tests/hidden/h3-scaled-sign/check.py