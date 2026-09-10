"""
Retry transports for HTTPX 0.28.1 — the oracle's implementation of the
clinker-mast feature.

HTTPX deliberately does not retry failed requests. These two classes wrap an
inner transport (BaseTransport / AsyncBaseTransport) and re-issue the request
when it fails with a transient error or comes back with a retryable status:

* any raised `httpx.TransportError` (connect/read/write/protocol/timeout)
* a response with status in {429, 500, 502, 503, 504}

An attempt is not repeated beyond `max_attempts`.  When a retryable response
carries a numeric `Retry-After` header, that many seconds elapse before the
next attempt; otherwise the next attempt starts immediately.  A response that
is abandoned for a retry has its stream closed so the transport stack does not
leak connections.  On the final attempt the caller sees the real outcome: the
raised error, or the response returned as-is.

Only the classes `RetryTransport` and `AsyncRetryTransport` are public here,
so the package's star-import export does not leak helper names.
"""

from __future__ import annotations

import anyio
import time
from types import TracebackType
from typing import Type

import httpx

from .base import AsyncBaseTransport, BaseTransport

_RETRYABLE_STATUS_CODES = frozenset({429, 500, 502, 503, 504})


def _retry_after_seconds(response: httpx.Response) -> float:
    """Seconds to wait before retrying, honoring a numeric Retry-After header."""
    header = response.headers.get("Retry-After")
    if header is None:
        return 0.0
    try:
        return max(0.0, float(header.strip()))
    except ValueError:
        # Unparseable Retry-After: proceed immediately rather than crashing.
        return 0.0


class RetryTransport(BaseTransport):
    def __init__(
        self,
        *,
        transport: httpx.BaseTransport | None = None,
        max_attempts: int = 3,
    ) -> None:
        if not isinstance(max_attempts, int) or max_attempts < 1:
            raise ValueError("max_attempts must be an int >= 1")
        self._transport = transport if transport is not None else httpx.HTTPTransport()
        self._max_attempts = max_attempts
        self._closed = False

    @property
    def is_closed(self) -> bool:
        return self._closed

    def close(self) -> None:
        if not self._closed:
            self._closed = True
            self._transport.close()

    def __enter__(self) -> "RetryTransport":
        return self

    def __exit__(
        self,
        exc_type: Type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        self.close()

    def handle_request(self, request: httpx.Request) -> httpx.Response:
        for attempt in range(1, self._max_attempts + 1):
            try:
                response = self._transport.handle_request(request)
            except httpx.TransportError:
                if attempt == self._max_attempts:
                    raise
                continue

            if response.status_code in _RETRYABLE_STATUS_CODES:
                if attempt == self._max_attempts:
                    return response
                delay = _retry_after_seconds(response)
                response.close()
                if delay > 0:
                    time.sleep(delay)
                continue

            return response

        raise RuntimeError("unreachable")  # pragma: no cover


class AsyncRetryTransport(AsyncBaseTransport):
    def __init__(
        self,
        *,
        transport: httpx.AsyncBaseTransport | None = None,
        max_attempts: int = 3,
    ) -> None:
        if not isinstance(max_attempts, int) or max_attempts < 1:
            raise ValueError("max_attempts must be an int >= 1")
        self._transport = transport if transport is not None else httpx.AsyncHTTPTransport()
        self._max_attempts = max_attempts
        self._closed = False

    @property
    def is_closed(self) -> bool:
        return self._closed

    async def aclose(self) -> None:
        """Close the wrapper and the wrapped transport (async transports close
        asynchronously in HTTPX)."""
        if not self._closed:
            self._closed = True
            await self._transport.aclose()

    async def __aenter__(self) -> "AsyncRetryTransport":
        return self

    async def __aexit__(
        self,
        exc_type: Type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        await self.aclose()

    async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
        for attempt in range(1, self._max_attempts + 1):
            try:
                response = await self._transport.handle_async_request(request)
            except httpx.TransportError:
                if attempt == self._max_attempts:
                    raise
                continue

            if response.status_code in _RETRYABLE_STATUS_CODES:
                if attempt == self._max_attempts:
                    return response
                delay = _retry_after_seconds(response)
                await response.aclose()
                if delay > 0:
                    await anyio.sleep(delay)
                continue

            return response

        raise RuntimeError("unreachable")  # pragma: no cover