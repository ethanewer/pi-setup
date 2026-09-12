"""Hidden case: the ValueError message must be preserved exactly.

The upstream regression test uses substring containment.  This case asserts
the message is preserved byte-for-byte, including for a bytes input value,
where the old code path would have echoed "b'raw bytes'" back.
"""

import click
import pytest


def test_value_error_message_preserved_exactly():
    def parse(value):
        raise ValueError("invalid, cannot parse")

    t = click.types.FuncParamType(parse)

    with pytest.raises(click.BadParameter) as exc_info:
        t.convert("a,b", None, None)

    assert exc_info.value.message == "invalid, cannot parse"


def test_bytes_input_message_not_echoed():
    def parse(value):
        raise ValueError("invalid, cannot parse")

    t = click.types.FuncParamType(parse)

    with pytest.raises(click.BadParameter) as exc_info:
        t.convert(b"raw bytes", None, None)

    assert exc_info.value.message == "invalid, cannot parse"
    assert "raw bytes" not in exc_info.value.message