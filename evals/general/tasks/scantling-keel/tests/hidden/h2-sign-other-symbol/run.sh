#!/bin/bash
# Hidden case h2: sign() appears on the SECOND symbol of the system,
# nonlinsolve([sign(y) - 1, x - y], [x, y]). The upstream regression test
# always puts sign(x) first; this exercises the same code path from an input
# it does not use. On the pre-fix tree the call crashes with a raw
# AttributeError; after the fix it must raise a clear solver-level
# NotImplementedError naming the solution type ('Interval').
set -u
cd /app/src || exit 1
SYMPY_SRC=/app/src python3 /tests/hidden/h2-sign-other-symbol/check.py