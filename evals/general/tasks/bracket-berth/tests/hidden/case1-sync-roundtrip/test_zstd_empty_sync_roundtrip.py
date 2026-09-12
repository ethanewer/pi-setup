"""Hidden case 1: zero-length zstd responses through a real sync client
round-trip, read via .read(), .iter_bytes() and .content (the upstream
regression test only builds a Response directly and touches .content)."""

import httpx


def handler(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, headers={"Content-Encoding": "zstd"}, content=b"")


def test_empty_zstd_read_via_sync_client():
    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        response = client.get("https://example.com/zero-length")
        assert response.read() == b""


def test_empty_zstd_iter_bytes_via_sync_client():
    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        response = client.get("https://example.com/chunked-empty")
        assert list(response.iter_bytes()) == []
        assert response.is_closed


def test_empty_zstd_content_via_sync_client():
    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        response = client.get("https://example.com/again")
        assert response.content == b""
        # idempotent once materialised
        assert response.content == b""


def test_empty_zstd_str_body_read_and_text():
    response = httpx.Response(
        200, headers=[(b"Content-Encoding", b"zstd")], content=""
    )
    assert response.read() == b""
    assert response.text == ""