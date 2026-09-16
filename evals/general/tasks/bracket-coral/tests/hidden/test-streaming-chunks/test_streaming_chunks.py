"""Hidden case 1: low-level MultipartDecoder driven the way a real server
receives an upload -- the part headers and file bytes arrive in an early
chunk, the closing boundary in a later one, with events drained in between.
The upstream regression test feeds the whole body in one receive_data call,
uses boundary b"foo", and inspects only the first event; here the boundary,
the file bytes, the chunk schedule and the reassembly contract all differ.
The file bytes reassembled across every Data event must equal the uploaded
bytes exactly."""
import pytest

from werkzeug.sansio.multipart import Data, Epilogue, MultipartDecoder, NeedData


def decode_chunked(boundary, body, content, chunk_sizes):
    if chunk_sizes == "split":
        # headers + full file bytes arrive first; the closing boundary later
        split = body.index(b"\r\n\r\n") + 2 + len(content)
        chunk_sizes = (split, len(body))
    decoder = MultipartDecoder(boundary)
    received = b""
    pos = 0
    for size in chunk_sizes:
        chunk = body[pos : pos + size]
        if not chunk:
            break
        decoder.receive_data(chunk)
        pos += len(chunk)
        while True:
            event = decoder.next_event()
            if isinstance(event, NeedData):
                break
            if isinstance(event, Data):
                received += event.data
            if isinstance(event, Epilogue):
                return received
    if pos < len(body):
        decoder.receive_data(body[pos:])
    decoder.receive_data(None)
    stale = 0
    while stale < 5:
        event = decoder.next_event()
        if isinstance(event, Data):
            received += event.data
        if isinstance(event, Epilogue):
            break
        stale = stale + 1 if isinstance(event, NeedData) else 0
    return received


def make_body(boundary, content):
    return (
        b"\r\n--" + boundary + b"\r\n"
        b'Content-Disposition: form-data; name="data"; filename="blob.bin"\r\n'
        b"Content-Type: application/octet-stream\r\n\r\n"
        + content
        + b"\r\n--" + boundary + b"--\r\n"
    )


CASES = [
    (b"stream-boundary-42", b"x\ry", "split"),
    (b"stream-boundary-42", b"\n\n", "split"),
    (b"stream-boundary-42", b"\n\nB", "split"),
    (b"stream-boundary-42", b"\r\nX\r\n", "split"),
    (b"another-boundary", b"alpha\nbeta", "split"),
    (b"stream-boundary-42", b"ab\ncd", (3, 7, 13, 11, 100)),
    (b"stream-boundary-42", b"nv\r\nx", (3, 7, 13, 11, 100)),
    (b"stream-boundary-42", b"sentinel", "split"),
]


@pytest.mark.parametrize("boundary,content,chunk_sizes", CASES)
def test_chunked_feed_round_trips(boundary, content, chunk_sizes):
    body = make_body(boundary, content)
    received = decode_chunked(boundary, body, content, chunk_sizes)
    assert received == content, (boundary, content, received)