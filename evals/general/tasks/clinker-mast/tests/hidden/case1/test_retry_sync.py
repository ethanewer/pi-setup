"""Hidden case 1 (sync): core retry semantics of httpx.RetryTransport.

All expectations are about observable behaviour of the public contract only;
no internals of the implementation are assumed beyond the wrapped transport.
"""

import time

import pytest

import httpx


class Countdown:
    """A MockTransport handler with a fixed script of outcomes."""

    def __init__(self, items):
        self.items = list(items)
        self.calls = 0
        self.seen_urls = []

    def __call__(self, request):
        self.calls += 1
        self.seen_urls.append(str(request.url))
        outcome = self.items.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        status, body, headers = outcome
        return httpx.Response(status, content=body, headers=headers)


def test_retries_after_transport_error() -> None:
    handler = Countdown([httpx.ConnectError("connection refused"), (200, b"ok", {})])
    transport = httpx.RetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=4
    )
    with httpx.Client(transport=transport) as client:
        response = client.get("https://example.com/a")
    assert response.status_code == 200
    assert response.content == b"ok"
    assert handler.calls == 2


def test_retries_after_timeout_error() -> None:
    handler = Countdown([httpx.ReadTimeout("slow"), httpx.WriteError("x"), (200, b"ok", {})])
    transport = httpx.RetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=5
    )
    with httpx.Client(transport=transport) as client:
        response = client.get("https://example.com/b")
    assert response.status_code == 200
    assert handler.calls == 3


def test_max_attempts_surfaces_last_transport_error() -> None:
    handler = Countdown([httpx.ConnectError("1"), httpx.ConnectError("2"), httpx.ConnectError("3")])
    transport = httpx.RetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=3
    )
    with httpx.Client(transport=transport) as client:
        with pytest.raises(httpx.ConnectError):
            client.get("https://example.com/c")
    assert handler.calls == 3


def test_max_attempts_one_means_no_retry() -> None:
    handler = Countdown([httpx.ConnectError("only"), (200, b"nope", {})])
    transport = httpx.RetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=1
    )
    with httpx.Client(transport=transport) as client:
        with pytest.raises(httpx.ConnectError):
            client.get("https://example.com/d")
    assert handler.calls == 1


def test_retries_retryable_5xx() -> None:
    handler = Countdown([(503, b"", {}), (200, b"recovered", {})])
    transport = httpx.RetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=3
    )
    with httpx.Client(transport=transport) as client:
        response = client.get("https://example.com/e")
    assert response.status_code == 200
    assert response.content == b"recovered"
    assert handler.calls == 2


def test_retries_500_and_504_and_502() -> None:
    for status in (500, 502, 504):
        handler = Countdown([(status, b"", {}), (200, b"ok", {})])
        transport = httpx.RetryTransport(
            transport=httpx.MockTransport(handler), max_attempts=3
        )
        with httpx.Client(transport=transport) as client:
            response = client.get(f"https://example.com/{status}")
        assert response.status_code == 200
        assert handler.calls == 2, f"status {status} should have been retried"


def test_does_not_retry_client_error() -> None:
    handler = Countdown([(404, b"gone", {})])
    transport = httpx.RetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=3
    )
    with httpx.Client(transport=transport) as client:
        response = client.get("https://example.com/f")
    assert response.status_code == 404
    assert response.content == b"gone"
    assert handler.calls == 1


def test_does_not_retry_501() -> None:
    handler = Countdown([(501, b"nope", {})])
    transport = httpx.RetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=3
    )
    with httpx.Client(transport=transport) as client:
        response = client.get("https://example.com/g")
    assert response.status_code == 501
    assert handler.calls == 1


def test_final_429_is_returned_when_attempts_exhausted() -> None:
    # 429 is a retryable status; once max_attempts is reached the last
    # response is returned as-is even though it is still retryable.
    handler = Countdown([(500, b"", {}), (429, b"", {"Retry-After": "0"})])
    transport = httpx.RetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=2
    )
    with httpx.Client(transport=transport) as client:
        response = client.get("https://example.com/h")
    assert response.status_code == 429
    assert handler.calls == 2


def test_429_with_retry_after_is_retried() -> None:
    handler = Countdown(
        [(429, b"", {"Retry-After": "0"}), (200, b"finally", {})]
    )
    transport = httpx.RetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=3
    )
    with httpx.Client(transport=transport) as client:
        response = client.get("https://example.com/i")
    assert response.status_code == 200
    assert response.content == b"finally"
    assert handler.calls == 2


def test_retry_after_delay_is_honoured() -> None:
    """A numeric Retry-After must cause a real wait before the next attempt."""
    handler = Countdown(
        [(503, b"", {"Retry-After": "1"}), (200, b"done", {})]
    )
    transport = httpx.RetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=3
    )
    start = time.monotonic()
    with httpx.Client(transport=transport) as client:
        response = client.get("https://example.com/j")
    elapsed = time.monotonic() - start
    assert response.status_code == 200
    assert handler.calls == 2
    assert elapsed >= 0.5, f"Retry-After of 1s was not honoured (elapsed {elapsed:.2f}s)"


def test_retry_after_unparseable_is_ignored() -> None:
    handler = Countdown(
        [(503, b"", {"Retry-After": "someday"}), (200, b"ok", {})]
    )
    transport = httpx.RetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=3
    )
    with httpx.Client(transport=transport) as client:
        response = client.get("https://example.com/k")
    assert response.status_code == 200
    assert handler.calls == 2


def test_last_retryable_response_is_returned_at_max_attempts() -> None:
    handler = Countdown([(503, b"down", {}), (503, b"still down", {})])
    transport = httpx.RetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=2
    )
    with httpx.Client(transport=transport) as client:
        response = client.get("https://example.com/l")
    assert response.status_code == 503
    assert response.content == b"still down"
    assert handler.calls == 2


def test_retry_failure_after_one_success_is_not_retried() -> None:
    handler = Countdown([(200, b"ok", {})])
    transport = httpx.RetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=3
    )
    with httpx.Client(transport=transport) as client:
        response = client.get("https://example.com/m")
    assert response.status_code == 200
    assert handler.calls == 1