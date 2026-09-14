#!/bin/bash
# Hidden case h1: the sign equation sign(x)+1=0 (interval (-oo,0)) paired
# with a different companion polynomial, x + y. The upstream regression test
# only uses sign(x)-1 with x*y-4 and x-y; this exercises the same solver
# code path from an input it does not use. On the pre-fix tree the call
# crashes with a raw TypeError; after the fix the call must raise a clear
# solver-level NotImplementedError naming the solution type ('Interval').
set -u
cd /app/src || exit 1
SYMPY_SRC=/app/src python3 /tests/hidden/h1-sign-plus-system/check.py