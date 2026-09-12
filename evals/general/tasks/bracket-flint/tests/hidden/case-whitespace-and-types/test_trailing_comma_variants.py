"""Hidden case 1 for bracket-flint: trailing-comma argname variants.

The upstream regression test only covers the bare "arg," spelling with string
values. This case drives the same unpacking decision from inputs the upstream
test does not use: whitespace around the single name and around the comma, and
value types other than str (ints, bytes). A comma-terminated single-name
string must unpack one-element tuples in every one of these variants.
"""

import pytest


@pytest.mark.parametrize("arg,", [("a",), ("b",)])
def test_plain_trailing_comma(arg):
    assert isinstance(arg, str)
    assert arg in ("a", "b")


@pytest.mark.parametrize("arg ,", [("c",), ("d",)])
def test_space_before_comma(arg):
    assert isinstance(arg, str)


@pytest.mark.parametrize("arg, ", [("e",), ("f",)])
def test_space_after_comma(arg):
    assert isinstance(arg, str)


@pytest.mark.parametrize("  arg  ,  ", [("g",), ("h",)])
def test_heavy_whitespace(arg):
    assert isinstance(arg, str)


@pytest.mark.parametrize("n,", [(1,), (2,), (3,)])
def test_integer_values(n):
    assert isinstance(n, int)
    assert n in (1, 2, 3)


@pytest.mark.parametrize("b,", [(b"\x01",), (b"\x02",)])
def test_bytes_values(b):
    assert isinstance(b, bytes)