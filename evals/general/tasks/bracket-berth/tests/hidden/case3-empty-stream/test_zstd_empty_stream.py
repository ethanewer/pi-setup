"""Hidden case 3: a zero-length STREAMING zstd body — a response whose body
is an iterator that yields no chunks at all — must decode to b'' without
raising, and a real non-empty zstd body must keep decoding afterwards (the
distinction the upstream fix is about: empty is not truncated)."""

import zstandard as zstd

import httpx


def test_empty_zstd_iterator_body():
    response = httpx.Response(
        200,
        headers=[(b"Content-Encoding", b"zstd")],
        content=iter([]),
    )
    assert response.read() == b""
    assert response.content == b""


def test_empty_then_real_zstd_body_still_decodes():
    empty = httpx.Response(
        200,
        headers=[(b"Content-Encoding", b"zstd")],
        content=iter([]),
    )
    assert empty.read() == b""

    body = b"payload bytes with some length to it"
    compressed = zstd.compress(body)
    full = httpx.Response(
        200,
        headers=[(b"Content-Encoding", b"zstd")],
        content=compressed,
    )
    assert full.content == body
    assert full.read() == body