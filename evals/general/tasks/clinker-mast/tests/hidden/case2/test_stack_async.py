"""Hidden case 2 (async): httpx.AsyncRetryTransport inside the client stack —
auth, event hooks, context management and response-stream hygiene.
"""

import pytest

import httpx


class TrackingAsyncStream(httpx.AsyncByteStream):
    """An async response stream that records whether it was closed."""

    def __init__(self, body: bytes = b""):
        self._body = body
        self.closed = False

    async def __aiter__(self):
        yield self._body

    async def aclose(self) -> None:
        self.closed = True


@pytest.mark.anyio
async def test_async_auth_on_every_attempt() -> None:
    attempts = []

    def handler(request):
        attempts.append(dict(request.headers))
        if len(attempts) == 1:
            raise httpx.ConnectError("nope")
        return httpx.Response(200, content=b"ok")

    async with httpx.AsyncClient(
        transport=httpx.AsyncRetryTransport(
            transport=httpx.MockTransport(handler), max_attempts=3
        ),
        auth=("user", "pass"),
    ) as client:
        response = await client.get("https://example.com/secure")
    assert response.status_code == 200
    assert len(attempts) == 2
    for headers in attempts:
        assert headers.get("authorization") == "Basic dXNlcjpwYXNz"


@pytest.mark.anyio
async def test_async_event_hooks_fire_once() -> None:
    events = []
    calls = {"n": 0}

    def handler(request):
        calls["n"] += 1
        if calls["n"] == 1:
            raise httpx.ReadTimeout("slow")
        return httpx.Response(200, content=b"ok")

    async def on_request(request):
        events.append("request")

    async def on_response(response):
        events.append("response")

    async with httpx.AsyncClient(
        transport=httpx.AsyncRetryTransport(
            transport=httpx.MockTransport(handler), max_attempts=3
        ),
        event_hooks={"request": [on_request], "response": [on_response]},
    ) as client:
        response = await client.get("https://example.com/hooked")
    assert response.status_code == 200
    assert calls["n"] == 2
    assert events == ["request", "response"]


@pytest.mark.anyio
async def test_async_abandoned_stream_closed() -> None:
    abandoned = []

    def handler(request):
        if not abandoned:
            stream = TrackingAsyncStream(b"partial")
            abandoned.append(stream)
            return httpx.Response(503, stream=stream)
        return httpx.Response(200, content=b"fresh")

    async with httpx.AsyncClient(
        transport=httpx.AsyncRetryTransport(
            transport=httpx.MockTransport(handler), max_attempts=3
        )
    ) as client:
        response = await client.get("https://example.com/hygiene")
    assert response.status_code == 200
    assert response.content == b"fresh"
    assert len(abandoned) == 1
    assert abandoned[0].closed, "abandoned async 503 stream was never closed"


@pytest.mark.anyio
async def test_async_default_transport_and_close() -> None:
    transport = httpx.AsyncRetryTransport(max_attempts=2)
    assert transport.is_closed is False
    await transport.aclose()
    assert transport.is_closed is True


@pytest.mark.anyio
async def test_async_context_manager() -> None:
    def handler(request):
        return httpx.Response(200, content=b"ok")

    async with httpx.AsyncRetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=2
    ) as transport:
        assert transport.is_closed is False
    assert transport.is_closed is True


@pytest.mark.anyio
async def test_async_request_body_replayed() -> None:
    bodies = []

    def handler(request):
        bodies.append(request.read())
        if len(bodies) == 1:
            raise httpx.ConnectError("boom")
        return httpx.Response(200, content=b"ok")

    async with httpx.AsyncClient(
        transport=httpx.AsyncRetryTransport(
            transport=httpx.MockTransport(handler), max_attempts=3
        )
    ) as client:
        response = await client.post("https://example.com/data", content=b"payload-123")
    assert response.status_code == 200
    assert bodies == [b"payload-123", b"payload-123"]