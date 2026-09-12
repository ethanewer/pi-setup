#!/usr/bin/env python3
"""Hidden case h3: .get() conversion semantics must not regress while fixing
the crash -- successful conversions still convert, ValueError still yields the
default, absent keys still yield the default, exceptions the converter raises
for NON-conversion reasons still propagate, and multi-valued .get() still
returns the converted first value.

Passes at the unfixed parent as well (it locks in the surrounding contract,
which must survive the fix untouched).
"""
from werkzeug.datastructures import MultiDict, TypeConversionDict

d = TypeConversionDict(ok="7", bad="not-an-int")

assert d.get("ok", type=int) == 7, "successful conversion must convert"
assert d.get("bad", default=3, type=int) == 3, "ValueError still returns the default"
assert d.get("missing", default=5, type=int) == 5, "absent key still returns the default"

# A converter whose own logic raises something other than ValueError/TypeError
# must let it propagate (here: ZeroDivisionError), before and after the fix.
try:
    d.get("ok", type=lambda v: 1 / 0)
except ZeroDivisionError:
    pass
else:
    raise AssertionError("ZeroDivisionError from the converter must propagate")

# .get() on multi-valued input converts and returns the first value
md = MultiDict([("n", "1"), ("n", "2")])
assert md.get("n", type=int) == 1, "MultiDict .get converts the first value"

print("h3 ok")