#!/usr/bin/env python3
"""Hidden case h2: the request-parsing MultiDict family -- the classes behind
request.args / request.form / request.files -- with an unparseable None value.

The upstream regression test only exercises plain TypeConversionDict; these
subclasses (and the exact "field present but None" shape) are not covered by
it. Every class here inherits TypeConversionDict.get (the method the fix
repairs); CombinedMultiDict has its own get() and is intentionally not part of
this case. At the unfixed parent each .get(...type=int) on a None value lets
TypeError escape and this script dies with a traceback.
"""
from werkzeug.datastructures import (
    ImmutableMultiDict,
    ImmutableOrderedMultiDict,
    MultiDict,
    OrderedMultiDict,
)

# MultiDict as request.args would be: a field present but empty/None
args = MultiDict([("page", "2"), ("flag", None)])
assert args.get("page", type=int) == 2, "convertible value still converts"
assert args.get("flag", default=-1, type=int) == -1, "int(None) must return the default"
assert args.get("absent", default=-1, type=int) == -1, "absent key returns default"

# OrderedMultiDict / Immutable variants
for cls in (OrderedMultiDict, ImmutableMultiDict, ImmutableOrderedMultiDict):
    d = cls([("flag", None)])
    assert d.get("flag", default=-1, type=int) == -1, \
        f"{cls.__name__}: int(None) must return the default"

# the same shape through the duplicate-value accessors used by forms
form = MultiDict([("tags", "a"), ("tags", "b"), ("retries", None)])
assert form.get("tags", type=str) == "a", "first value converts"
assert form.get("retries", default=3, type=int) == 3, "int(None) must return the default"

print("h2 ok")