"""Hidden case for bracket-ember: pickle round-trip across payloads and
protocols.

The upstream regression test checks a single (msg, doc, pos) payload with the
default pickle protocol. This case drives the same code path from many
payloads docs -- including trailing data, truncated documents, unicode and a
raw control character -- across pickle protocols 0, 1, 2, 4, 5 and HIGHEST,
and asserts the reconstructed object's msg/doc/pos attributes and repr are
byte-for-byte the original's. At the pinned parent commit the round-trip
raises TypeError (doc and pos are dropped); after the fix every protocol must
round-trip cleanly.
"""

import copy
import pickle

import pytest

from requests.exceptions import JSONDecodeError

CTRL = "\x01"
PAYLOADS = [
    # golden-style: trailing data after a complete object
    ("Extra data", '{"responseCode":["706"],"data":null}{"responseCode":["706"],"data":null}', 36),
    # truncated document, pos at EOF
    ("Expecting value", "[1, 2, ", 7),
    # missing value for a key
    ("Expecting value", '{"a": 1, "b": }', 16),
    # unicode document
    ("Expecting value", '{"\u043a\u043b\u044e\u0447": }', 11),
    # newline inside the document shifts the reported column, not the pos
    ("Unterminated string", '{\n  "a": "open\n  still open', 25),
    # doc with a raw control character (json forbids it in strings)
    ("Invalid control character", '{"a": "' + CTRL + '"}', 7),
    # pos at the very start of the doc
    ("Expecting property name enclosed in double quotes", '{"a": 1}', 0),
]


def _roundtrip(error, protocol):
    return pickle.loads(pickle.dumps(error, protocol=protocol))


@pytest.mark.parametrize("payload", PAYLOADS)
@pytest.mark.parametrize("protocol", sorted({0, 1, 2, 4, 5, pickle.HIGHEST_PROTOCOL}))
def test_roundtrip_preserves_attrs_and_repr(payload, protocol):
    error = JSONDecodeError(*payload)
    back = _roundtrip(error, protocol)
    assert repr(back) == repr(error), (protocol, repr(back), repr(error))
    assert back.msg == error.msg, protocol
    assert back.doc == error.doc, protocol
    assert back.pos == error.pos, protocol


def test_roundtrip_is_stable_across_repeated_trips():
    error = JSONDecodeError("Extra data", '{"a":1}{"a":1}', 7)
    back = _roundtrip(_roundtrip(error, 2), 2)
    assert repr(back) == repr(error)
    assert (back.msg, back.doc, back.pos) == (error.msg, error.doc, error.pos)


def test_copy_and_deepcopy_use_the_same_reconstruction_path():
    error = JSONDecodeError("Expecting value", "[1, 2, ", 7)
    for copied in (copy.copy(error), copy.deepcopy(error)):
        assert repr(copied) == repr(error)
        assert (copied.msg, copied.doc, copied.pos) == (error.msg, error.doc, error.pos)


def test_reconstructed_object_is_a_value_error_with_the_document_details():
    error = JSONDecodeError("Extra data", '{"a":1}{"a":1}', 7)
    back = _roundtrip(error, pickle.HIGHEST_PROTOCOL)
    assert isinstance(back, ValueError)
    assert str(back) == str(error)