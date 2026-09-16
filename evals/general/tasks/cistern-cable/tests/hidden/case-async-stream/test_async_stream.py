"""Hidden case for cistern-cable: the asynchronous aiter_text() path.

The upstream regression test only exercises the synchronous iter_text().  The
async path shares the same text chunker, so the same bug appeared there: the
final decoder flush surfaced as a spurious trailing ''.  These tests drive
aiter_text() over async-generator bodies, including a UTF-8 document split
across an async chunk boundary, and require the exact chunk sequence plus
exact reconstruction.
"""

import httpx
import pytest


async def _agen(chunks):
    for chunk in chunks:
        yield chunk


@pytest.mark.anyio
async def test_async_stream_exact_chunks():
    body = [b"alpha", b" beta", b" gamma"]
    response = httpx.Response(200, content=_agen(body))
    parts = [part async for part in response.aiter_text()]
    assert parts == ["alpha", " beta", " gamma"]


@pytest.mark.anyio
async def test_async_stream_join_multibyte():
    doc = "héllo wörld 🌍"
    data = doc.encode("utf-8")
    mid = len(data) // 2
    response = httpx.Response(200, content=_agen([data[:mid], data[mid:]]))
    parts = [part async for part in response.aiter_text()]
    assert parts[-1] != ""
    assert "" not in parts
    assert "".join(parts) == doc


@pytest.mark.anyio
async def test_async_stream_empty_transport_chunk():
    response = httpx.Response(200, content=_agen([b"abc", b"", b"def"]))
    parts = [part async for part in response.aiter_text()]
    assert parts == ["abc", "def"]