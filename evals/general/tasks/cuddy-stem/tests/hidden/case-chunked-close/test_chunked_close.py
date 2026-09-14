"""Hidden case for cuddy-stem: close status split across chunks.

A Close frame may arrive at the reader over several TCP segments; the reader
buffers the partial payload and validates the close code only once the whole
payload has arrived.  This case feeds the 2-byte status code one byte at a
time and asserts that the protocol error still fires on the byte that
completes the code, and that no partial WSMessageClose ever leaks out.
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


def test_1006_split_across_chunks_still_rejected(reader) -> None:
    r, out = reader
    frame = close_frame(1006)
    assert len(out._buffer) == 0
    # Header + first status byte: frame not complete, nothing queued.
    err, left = r.feed_data(frame[:3])
    assert (err, left) == (False, b"")
    assert len(out._buffer) == 0
    # Second status byte completes the payload: must raise here.
    with pytest.raises(WebSocketError) as ctx:
        r._feed_data(frame[3:])
    assert ctx.value.code == WSCloseCode.PROTOCOL_ERROR
    assert len(out._buffer) == 0


def test_1000_split_across_chunks_accepted(reader) -> None:
    r, out = reader
    frame = close_frame(1000)
    r.feed_data(frame[:3])
    r.feed_data(frame[3:])
    assert out.exception() is None
    assert len(out._buffer) == 1
    assert out._buffer[0].data == 1000