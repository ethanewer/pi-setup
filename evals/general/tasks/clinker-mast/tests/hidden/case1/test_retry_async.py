"""Hidden case 1 (async): core retry semantics of httpx.AsyncRetryTransport."""

import time

import pytest

import httpx


class AsyncCountdown:
    """An async MockTransport handler with a fixed script of outcomes."""

    def __init__(self, items):
        self.items = list(items)
        self.calls = 0

    def __call__(self, request):
        self.calls += 1
        outcome = self.items.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        status, body, headers = outcome
        return httpx.Response(status, content=body, headers=headers)


@pytest.mark.anyio
async def test_async_retries_transport_error() -> None:
    handler = AsyncCountdown([httpx.ConnectError("refused"), (200, b"ok", {})])
    transport = httpx.AsyncRetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=4
    )
    async with httpx.AsyncClient(transport=transport) as client:
        response = await client.get("https://example.com/a")
    assert response.status_code == 200
    assert response.content == b"ok"
    assert handler.calls == 2


@pytest.mark.anyio
async def test_async_two_errors_then_success() -> None:
    handler = AsyncCountdown(
        [httpx.ReadTimeout("slow"), httpx.ConnectError("x"), (200, b"ok", {})]
    )
    transport = httpx.AsyncRetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=5
    )
    async with httpx.AsyncClient(transport=transport) as client:
        response = await client.get("https://example.com/b")
    assert response.status_code == 200
    assert handler.calls == 3


@pytest.mark.anyio
async def test_async_max_attempts_surfaces_last_error() -> None:
    handler = AsyncCountdown(
        [httpx.ConnectError("1"), httpx.ConnectError("2"), httpx.ConnectError("3")]
    )
    transport = httpx.AsyncRetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=3
    )
    async with httpx.AsyncClient(transport=transport) as client:
        with pytest.raises(httpx.ConnectError):
            await client.get("https://example.com/c")
    assert handler.calls == 3


@pytest.mark.anyio
async def test_async_max_attempts_one_no_retry() -> None:
    handler = AsyncCountdown([httpx.ConnectError("only"), (200, b"nope", {})])
    transport = httpx.AsyncRetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=1
    )
    async with httpx.AsyncClient(transport=transport) as client:
        with pytest.raises(httpx.ConnectError):
            await client.get("https://example.com/d")
    assert handler.calls == 1


@pytest.mark.anyio
async def test_async_retries_retryable_5xx() -> None:
    for status in (500, 502, 503, 504):
        handler = AsyncCountdown([(status, b"", {}), (200, b"ok", {})])
        transport = httpx.AsyncRetryTransport(
            transport=httpx.MockTransport(handler), max_attempts=3
        )
        async with httpx.AsyncClient(transport=transport) as client:
            response = await client.get(f"https://example.com/{status}")
        assert response.status_code == 200
        assert handler.calls == 2, f"status {status} should have been retried"


@pytest.mark.anyio
async def test_async_does_not_retry_client_error() -> None:
    handler = AsyncCountdown([(404, b"gone", {})])
    transport = httpx.AsyncRetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=3
    )
    async with httpx.AsyncClient(transport=transport) as client:
        response = await client.get("https://example.com/f")
    assert response.status_code == 404
    assert handler.calls == 1


@pytest.mark.anyio
async def test_async_429_with_retry_after_retried() -> None:
    handler = AsyncCountdown(
        [(429, b"", {"Retry-After": "0"}), (200, b"finally", {})]
    )
    transport = httpx.AsyncRetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=3
    )
    async with httpx.AsyncClient(transport=transport) as client:
        response = await client.get("https://example.com/i")
    assert response.status_code == 200
    assert response.content == b"finally"
    assert handler.calls == 2


@pytest.mark.anyio
async def test_async_retry_after_delay_honoured() -> None:
    handler = AsyncCountdown([(503, b"", {"Retry-After": "1"}), (200, b"done", {})])
    transport = httpx.AsyncRetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=3
    )
    start = time.monotonic()
    async with httpx.AsyncClient(transport=transport) as client:
        response = await client.get("https://example.com/j")
    elapsed = time.monotonic() - start
    assert response.status_code == 200
    assert handler.calls == 2
    assert elapsed >= 0.5, f"Retry-After of 1s was not honoured (elapsed {elapsed:.2f}s)"


@pytest.mark.anyio
async def test_async_final_retryable_response_returned() -> None:
    handler = AsyncCountdown([(503, b"down", {}), (503, b"still", {})])
    transport = httpx.AsyncRetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=2
    )
    async with httpx.AsyncClient(transport=transport) as client:
        response = await client.get("https://example.com/l")
    assert response.status_code == 503
    assert response.content == b"still"
    assert handler.calls == 2