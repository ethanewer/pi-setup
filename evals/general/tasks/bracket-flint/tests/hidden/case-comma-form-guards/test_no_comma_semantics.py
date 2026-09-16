"""Hidden case 2 for bracket-flint: the no-comma forms must keep their semantics.

A correct fix changes only what a TRAILING COMMA means: it must not disturb the
forms that already work. These guards assert that a single-name string without
a comma still receives one-element tuple values wrapped (as a whole), that the
tuple form still unpacks them, that multi-name strings still unpack each tuple,
and that a single name with trailing whitespace but no comma keeps its
no-comma semantics.

At the buggy commit every test here already passes; after a fix that
over-generalises (removing tuple-wrapping for ALL single-name strings) these
tests fail. They are what makes passing the golden test alone insufficient.
"""

import pytest


@pytest.mark.parametrize("arg", [("a",), ("b",)])
def test_no_comma_string_wraps_tuples(arg):
    # no comma: each argvalue is passed through as-is, tuples stay whole
    assert isinstance(arg, tuple)
    assert arg in (("a",), ("b",))


@pytest.mark.parametrize(("arg",), [("a",), ("b",)])
def test_tuple_form_still_unpacks(arg):
    assert isinstance(arg, str)
    assert arg in ("a", "b")


@pytest.mark.parametrize("left,right", [("a", "b"), ("c", "d")])
def test_multi_name_string_still_unpacks(left, right):
    assert isinstance(left, str)
    assert isinstance(right, str)


@pytest.mark.parametrize("arg", ["single"])
def test_no_comma_string_plain_value(arg):
    assert arg == "single"


@pytest.mark.parametrize("arg ", [("t",), ("u",)])
def test_trailing_space_without_comma_wraps(arg):
    # "arg " has no comma: it keeps the no-comma (wrapped) semantics
    assert isinstance(arg, tuple)