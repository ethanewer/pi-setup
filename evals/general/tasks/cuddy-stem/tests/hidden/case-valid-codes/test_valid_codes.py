"""Hidden case for cuddy-stem: valid on-wire close status codes stay accepted.

The upstream regression test only asserts rejection of 1004/1005/1006/1015.
This case pins the other side of the contract: every status code RFC 6455
allows on the wire -- the defined codes 1000-1014 other than 1006, and the
private-use range 3000-4999 -- must be accepted with the code preserved and
must not raise a protocol error.  A fix that over-rejects (for example by
rejecting every code below 3000, or by dropping the whole ALLOWED_CLOSE_CODES
set) fails here.
"""

import struct
from unittest import mock

import pytest
from aiohttp._websocket.reader import WebSocketDataQueue
from aiohttp.http import WebSocketError, WebSocketReader, WSCloseCode


def close_frame(code: int) -> bytes:
    return bytes([0x88, 2]) + struct.pack("!H", code)


@pytest.fixture()
def reader(event_loop):
    out = WebSocketDataQueue(mock.Mock(_reading_paused=False), 2 ** 16, loop=event_loop)
    r = WebSocketReader(out, 4 * 1024 * 1024, compress=True, decode_text=True)
    return r, out


VALID = [
    1000,  # OK (normal closure)
    1001,  # GOING_AWAY
    1002,  # PROTOCOL_ERROR (a peer may send this)
    1003,  # UNSUPPORTED_DATA
    1007,  # INVALID_TEXT
    1008,  # POLICY_VIOLATION
    1009,  # MESSAGE_TOO_BIG
    1010,  # MANDATORY_EXTENSION
    1011,  # INTERNAL_ERROR
    1012,  # SERVICE_RESTART
    1013,  # TRY_AGAIN_LATER
    1014,  # BAD_GATEWAY
    3000,  # private use (lower bound)
    3001,
    4000,
    4999,  # private use (upper bound)
]


@pytest.mark.parametrize("code", VALID)
def test_valid_close_code_accepted(reader, code: int) -> None:
    r, out = reader
    err, left = r.feed_data(close_frame(code))
    assert err is False
    assert left == b""
    assert out.exception() is None
    assert len(out._buffer) == 1
    assert out._buffer[0].data == code
    assert out._buffer[0].size == 2


def test_1006_still_rejected_control(reader) -> None:
    """Control: the reserved code this whole task is about stays rejected."""
    r, out = reader
    with pytest.raises(WebSocketError) as ctx:
        r._feed_data(close_frame(1006))
    assert ctx.value.code == WSCloseCode.PROTOCOL_ERROR
    assert len(out._buffer) == 0