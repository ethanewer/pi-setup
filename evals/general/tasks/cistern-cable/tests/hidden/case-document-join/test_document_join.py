"""Hidden case for cistern-cable: rebuilding a document from iter_text().

The upstream regression test streams two ASCII chunks.  This case streams a
real UTF-8 document whose chunk boundaries cut multibyte characters in half,
asserts the exact chunk sequence (no trailing or interior empty strings), and
checks that joining the chunks reproduces the document exactly.  It also
covers a single-piece (one-chunk) stream and a stream whose final transport
chunk is empty, both of which produced a spurious trailing '' before the fix.
"""

import httpx

DOC = "Grüße aus München — farewell, добро пожаловать! 🌍"


def _chunks(text: str, n: int):
    data = text.encode("utf-8")
    return [data[i : i + n] for i in range(0, len(data), n)]


def test_document_join_exact_chunks():
    body = _chunks(DOC, 7)
    assert len(body) >= 5, body
    response = httpx.Response(200, content=iter(body))
    parts = list(response.iter_text())
    assert parts[-1] != ""  # the bug appended a trailing empty piece
    assert "" not in parts
    assert "".join(parts) == DOC


def test_document_join_trailing_empty_transport_chunk():
    # A transport may deliver an empty final chunk; it must not surface as an
    # empty text piece.
    body = _chunks("abc\ndef\nghi", 4) + [b""]
    response = httpx.Response(200, content=iter(body))
    parts = list(response.iter_text())
    # Each raw byte chunk surfaces as exactly one text piece; the empty final
    # transport chunk must not surface at all, and crucially nothing extra may
    # be appended after 'ghi'.
    assert parts == ["abc\n", "def\n", "ghi"]
    assert "".join(parts) == "abc\ndef\nghi"


def test_single_chunk_stream_exact():
    response = httpx.Response(200, content=iter((b"single piece",)))
    assert list(response.iter_text()) == ["single piece"]


def test_fixed_chunk_size_still_exact():
    # The buffered (chunk_size set) path must keep its exact semantics too.
    response = httpx.Response(200, content=iter((b"Hello, ", b"world!")))
    assert list(response.iter_text(chunk_size=5)) == ["Hello", ", wor", "ld!"]

    response = httpx.Response(200, content=iter((b"Hello, world!",)))
    assert list(response.iter_text(chunk_size=20)) == ["Hello, world!"]