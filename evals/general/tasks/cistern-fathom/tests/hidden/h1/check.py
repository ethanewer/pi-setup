#!/usr/bin/env python3
"""Hidden case h1: TypeConversionDict.get with converter/input combinations
the upstream regression test does not use (float(None), int(list),
int(dict)) plus the conversion/missing-key neighbors.

At the unfixed parent each unconvertible case lets TypeError escape .get()
and this script dies with a traceback (nonzero exit). With the fix, every
assertion holds.
"""
from werkzeug.datastructures import TypeConversionDict

# float(None) is a TypeError inside the converter -> default, never raise
assert TypeConversionDict(baz=None).get("baz", default=-1, type=float) == -1, \
    "float(None) must return the default"
assert TypeConversionDict(baz=None).get("baz", default="d", type=int) == "d", \
    "int(None) must return the default"

# int(list) and int(dict) are TypeErrors too -> default
d2 = TypeConversionDict(items=[1, 2, 3], mapping={"a": 1})
assert d2.get("items", default="d", type=int) == "d", "int(list) must return the default"
assert d2.get("mapping", default="d", type=int) == "d", "int(dict) must return the default"

# conversion still works, even for the same key with a different converter
assert d2.get("mapping", default="d", type=len) == 1, "len(dict) still converts"

# absent key still returns the default
assert TypeConversionDict().get("absent", default=99, type=int) == 99, \
    "absent key must return the default"

print("h1 ok")