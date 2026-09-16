"""Hidden case for cuddy-stem: masked (client-to-server) and extended frames.

The upstream regression test builds unmasked, short Close frames.  A real
browser or client peer MASKS every frame it sends (RFC 6455 section 5.3), and
long frames switch to the extended 16-bit length encoding.  This case drives
the same validation path through masked framing (4-byte mask, XOR-unmasked
payload) and through the extended length encoding, with status 1006 rejected
and status 1000 accepted.
"""

import struct
from unittest import mock

import pytest
from aiohttp._websocket.reader import WebSocketDataQueue
from aiohttp.http import WebSocketError, WebSocketReader, WSCloseCode

MASK = b"\x11\x22\x33\x44"


def xor_mask(payload: bytes) -> bytes:
    return bytes(b ^ MASK[i % 4] for (i, b) in enumerate(payload))


def masked_close_frame(code: int, reason: bytes = b"") -> bytes:
    payload = struct.pack("!H", code) + reason
    n = len(payload)
    if n < 126:
        header = bytes([0x88, 0x80 | n])
    else:
        header = bytes([0x88, 0x80 | 126]) + struct.pack("!H", n)
    return header + MASK + xor_mask(payload)


@pytest.fixture()
def reader(event_loop):
    out = WebSocketDataQueue(mock.Mock(_reading_paused=False), 2 ** 16, loop=event_loop)
    r = WebSocketReader(out, 4 * 1024 * 1024, compress=True, decode_text=True)
    return r, out


def test_masked_close_1006_rejected(reader) -> None:
    r, out = reader
    with pytest.raises(WebSocketError) as ctx:
        r._feed_data(masked_close_frame(1006))
    assert ctx.value.code == WSCloseCode.PROTOCOL_ERROR
    assert len(out._buffer) == 0


def test_masked_close_1006_rejected_with_reason(reader) -> None:
    r, out = reader
    with pytest.raises(WebSocketError) as ctx:
        r._feed_data(masked_close_frame(1006, b"gone"))
    assert ctx.value.code == WSCloseCode.PROTOCOL_ERROR


def test_masked_close_1000_accepted(reader) -> None:
    r, out = reader
    r._feed_data(masked_close_frame(1000, b"bye"))
    assert out.exception() is None
    assert out._buffer[0].data == 1000
    assert out._buffer[0].extra == "bye"


def test_extended_length_masked_close_1006_rejected(reader) -> None:
    r, out = reader
    # 2 code bytes + 124 reason bytes forces the 16-bit length encoding.
    frame = masked_close_frame(1006, b"x" * 124)
    with pytest.raises(WebSocketError) as ctx:
        r._feed_data(frame)
    assert ctx.value.code == WSCloseCode.PROTOCOL_ERROR