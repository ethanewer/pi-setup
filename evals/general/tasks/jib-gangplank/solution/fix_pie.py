#!/usr/bin/env python3
"""Apply the minimal upstream fix for the all-zero pie wedges bug.

Axes.pie normalizes the wedge sizes by their sum and then constructs wedges
from the resulting angles; when every wedge size is zero the sum is zero,
the angles become NaN, and the call dies deep inside the path-drawing code
with 'ValueError: cannot convert float NaN to integer'. The fix rejects the
input up front, right after the sum is computed, with a clear message.
"""
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()

old = "        sx = x.sum()\n"
new = ("        sx = x.sum()\n"
       "\n"
       "        if sx == 0:\n"
       "            raise ValueError('All wedge sizes are zero')\n")

assert src.count(old) == 1, "sx = x.sum() not found exactly once in %s" % path
assert "'All wedge sizes are zero'" not in src, "the fix appears to be already applied"

open(path, "w", encoding="utf-8").write(src.replace(old, new))
print("patched %s" % path)