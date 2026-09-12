"""Hidden case: non-string input values.

The upstream regression test only feeds the string "nope".  These cases feed
an int value, where the raw-input echo path would show "42"/"1729" instead of
the ValueError's message, and verify the empty-message fallback also works
for a non-string value.
"""

import click
import pytest


def test_nonstring_input_uses_value_error_message():
    def parse(value):
        raise ValueError("must be a positive integer")

    t = click.types.FuncParamType(parse)

    with pytest.raises(click.BadParameter) as exc_info:
        t.convert(42, None, None)

    assert "must be a positive integer" in exc_info.value.message
    assert "42" not in exc_info.value.message


def test_empty_message_falls_back_to_raw_nonstring_value():
    def parse(value):
        raise ValueError()

    t = click.types.FuncParamType(parse)

    with pytest.raises(click.BadParameter) as exc_info:
        t.convert(1729, None, None)

    assert "1729" in exc_info.value.message