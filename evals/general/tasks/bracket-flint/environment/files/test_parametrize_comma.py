"""Probe: single-argument parametrize with a comma-terminated string name.

This file demonstrates the bug in the pinned pytest checkout at /app/src.
`@pytest.mark.parametrize("arg,", [("a",), ("b",)])` passes a single argument
name as a *comma-terminated* string. It should behave exactly like the tuple
form `("arg",)`: each one-element tuple from the argvalues list is unpacked and
the test receives its single element ("a", then "b").

In this checkout the test instead receives the whole one-element tuple and
fails with something like `assert isinstance(('a',), str)`.

The second test shows the same argname string with plain scalar values, which
work in both the buggy and the fixed implementations and must keep working.
"""

import pytest

SCENARIOS = [("a",), ("b",)]


@pytest.mark.parametrize("arg,", SCENARIOS)
def test_trailing_comma_unpacks_tuples(arg):
    # one-element tuples must be unpacked: 'arg' is "a" then "b", never ("a",)
    assert isinstance(arg, str)
    assert arg in ("a", "b")


@pytest.mark.parametrize("arg,", ["x", "y"])
def test_trailing_comma_plain_values(arg):
    # scalar values continue to be passed through directly
    assert isinstance(arg, str)
    assert arg in ("x", "y")