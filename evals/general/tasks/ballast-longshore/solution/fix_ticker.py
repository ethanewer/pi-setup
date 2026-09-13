#!/usr/bin/env python3
"""Apply the minimal upstream fix for matplotlib issue #29532.

ScalarFormatter.set_useOffset decided between the boolean branch and the
numeric branch with a membership test against a list literal:

    if val in [True, False]:

which dispatches on *value equality*, so the numeric values 0 and 1 (and any
object comparing equal to them, e.g. numpy scalars) are captured by the
boolean branch: set_useOffset(1) reset the offset to 0 and turned automatic
offset mode on. The fix dispatches on actual type instead, so that only real
bool instances toggle the mode and every number is stored as an offset.
"""
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()

old = "        if val in [True, False]:\n"
new = "        if isinstance(val, bool):\n"

assert src.count(old) == 1, "buggy dispatch line not found exactly once in %s" % path
assert new not in src, "the fix appears to be already applied"

open(path, "w", encoding="utf-8").write(src.replace(old, new))
print("patched %s" % path)