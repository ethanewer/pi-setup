"""Hidden case 3 for bracket-flint: indirect and ids with the trailing comma.

The upstream regression test uses plain argvalues only. This case exercises the
same unpacking decision with `indirect=True` (each one-element tuple must be
passed through to the fixture unpacked, so `request.param` is the string, not a
one-element tuple) and with explicit `ids=` -- spellings of the same code path
the upstream test does not cover.
"""

import pytest


@pytest.fixture
def val(request):
    return request.param


@pytest.mark.parametrize("val,", [("a",), ("b",)], indirect=True)
def test_indirect_trailing_comma(val):
    assert isinstance(val, str)
    assert val in ("a", "b")


@pytest.mark.parametrize("arg,", [("w",), ("z",)], ids=["w-case", "z-case"])
def test_ids_with_trailing_comma(arg):
    assert isinstance(arg, str)