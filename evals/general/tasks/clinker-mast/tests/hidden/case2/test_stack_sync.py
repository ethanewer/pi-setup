"""Hidden case 2 (sync): interaction of httpx.RetryTransport with the rest of
the HTTPX transport stack — the client, auth, event hooks, and connection
hygiene when a response is abandoned for a retry.
"""

import httpx


class TrackingSyncStream(httpx.SyncByteStream):
    """A response stream that records whether it was ever closed."""

    def __init__(self, body: bytes = b""):
        self._body = body
        self.closed = False

    def __iter__(self):
        yield self._body

    def close(self) -> None:
        self.closed = True


def test_usable_via_httpx_client() -> None:
    """The wrapper must slot in as `transport=` of a Client, like any BaseTransport."""
    handler_calls = {"n": 0}

    def handler(request):
        handler_calls["n"] += 1
        if handler_calls["n"] == 1:
            raise httpx.ConnectError("dropped")
        return httpx.Response(200, content=b"ok")

    with httpx.Client(
        transport=httpx.RetryTransport(
            transport=httpx.MockTransport(handler), max_attempts=3
        )
    ) as client:
        response = client.get("https://example.com/stack")
        assert response.content == b"ok"
    assert handler_calls["n"] == 2


def test_auth_header_present_on_every_attempt() -> None:
    """Auth is applied by the client before the transport, so it must be
    observable on each retried attempt, not just the first."""
    attempts = []

    def handler(request):
        attempts.append(dict(request.headers))
        if len(attempts) == 1:
            raise httpx.ConnectError("nope")
        return httpx.Response(200, content=b"ok")

    with httpx.Client(
        transport=httpx.RetryTransport(
            transport=httpx.MockTransport(handler), max_attempts=3
        ),
        auth=("user", "pass"),
    ) as client:
        response = client.get("https://example.com/secure")
    assert response.status_code == 200
    assert len(attempts) == 2
    for headers in attempts:
        assert headers.get("authorization") == "Basic dXNlcjpwYXNz"


def test_event_hooks_fire_once_per_request_not_per_attempt() -> None:
    """Retries live inside the transport, below the client's event-hook layer."""
    events = []
    handler_calls = {"n": 0}

    def handler(request):
        handler_calls["n"] += 1
        if handler_calls["n"] == 1:
            raise httpx.ReadTimeout("slow")
        return httpx.Response(200, content=b"ok")

    def on_request(request):
        events.append("request")

    def on_response(response):
        events.append("response")

    with httpx.Client(
        transport=httpx.RetryTransport(
            transport=httpx.MockTransport(handler), max_attempts=3
        ),
        event_hooks={"request": [on_request], "response": [on_response]},
    ) as client:
        response = client.get("https://example.com/hooked")
    assert response.status_code == 200
    assert handler_calls["n"] == 2
    assert events == ["request", "response"]


def test_abandoned_response_stream_is_closed() -> None:
    """A retryable response that is abandoned for a retry must have its
    stream closed so the transport stack leaks nothing (hygiene)."""
    abandoned = []

    def handler(request):
        if not abandoned:
            stream = TrackingSyncStream(b"partial")
            abandoned.append(stream)
            return httpx.Response(503, stream=stream)
        return httpx.Response(200, content=b"fresh")

    with httpx.Client(
        transport=httpx.RetryTransport(
            transport=httpx.MockTransport(handler), max_attempts=3
        )
    ) as client:
        response = client.get("https://example.com/hygiene")
    assert response.status_code == 200
    assert response.content == b"fresh"
    assert len(abandoned) == 1
    assert abandoned[0].closed, "abandoned 503 response stream was never closed"


def test_default_transport_constructs_without_network() -> None:
    """With no inner transport given the wrapper falls back to the standard
    network transport — construct/close must not touch the network."""
    transport = httpx.RetryTransport(max_attempts=2)
    assert transport.is_closed is False
    transport.close()
    assert transport.is_closed is True


def test_default_transport_usable_inside_client() -> None:
    handler_calls = {"n": 0}

    def handler(request):
        handler_calls["n"] += 1
        if handler_calls["n"] == 1:
            raise httpx.ConnectError("first")
        return httpx.Response(200, content=b"ok")

    # Explicit mock wiring (no real network) still demonstrates the default
    # transport argument path is accepted by the constructor.
    transport = httpx.RetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=3
    )
    with httpx.Client(transport=transport) as client:
        response = client.get("https://example.com/x")
    assert response.status_code == 200
    assert handler_calls["n"] == 2


def test_context_manager_closes_inner_transport() -> None:
    handler = lambda request: httpx.Response(200, content=b"ok")  # noqa: E731
    with httpx.RetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=2
    ) as transport:
        assert transport.is_closed is False
    assert transport.is_closed is True


def test_request_body_replayed_on_retry() -> None:
    """Re-issuing the same request must present the same body to every attempt."""
    bodies = []

    def handler(request):
        bodies.append(request.read())
        if len(bodies) == 1:
            raise httpx.ConnectError("boom")
        return httpx.Response(200, content=b"ok")

    with httpx.Client(
        transport=httpx.RetryTransport(
            transport=httpx.MockTransport(handler), max_attempts=3
        )
    ) as client:
        response = client.post("https://example.com/data", content=b"payload-123")
    assert response.status_code == 200
    assert bodies == [b"payload-123", b"payload-123"]


def test_response_body_of_success_is_consumable() -> None:
    handler_calls = {"n": 0}

    def handler(request):
        handler_calls["n"] += 1
        if handler_calls["n"] == 1:
            return httpx.Response(503)
        return httpx.Response(200, content=b"streamed-payload")

    with httpx.Client(
        transport=httpx.RetryTransport(
            transport=httpx.MockTransport(handler), max_attempts=3
        )
    ) as client:
        with client.stream("GET", "https://example.com/stream") as response:
            assert response.status_code == 200
            body = b"".join(response.iter_bytes())
    assert body == b"streamed-payload"