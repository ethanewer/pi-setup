"""Hidden case 3 (part 2): edge cases of the retrying transport beyond the
core semantics and stack interaction covered in cases 1 and 2.
"""

import pytest

import httpx


class Scripted:
    def __init__(self, items):
        self.items = list(items)
        self.calls = 0

    def __call__(self, request):
        self.calls += 1
        outcome = self.items.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        status, body = outcome
        return httpx.Response(status, content=body)


def test_max_attempts_less_than_one_rejected() -> None:
    for bad in (0, -1, -5):
        with pytest.raises((ValueError, TypeError)):
            httpx.RetryTransport(
                transport=httpx.MockTransport(lambda r: httpx.Response(200)),
                max_attempts=bad,
            )
        with pytest.raises((ValueError, TypeError)):
            httpx.AsyncRetryTransport(max_attempts=bad)


def test_max_attempts_non_integer_rejected() -> None:
    with pytest.raises((ValueError, TypeError)):
        httpx.RetryTransport(max_attempts=3.5)


def test_mixed_failure_then_success_sequence() -> None:
    """A retryable response followed by a transport error followed by success:
    each step must re-attempt, capped by max_attempts."""
    handler = Scripted(
        [httpx.ConnectError("a"), (503, b""), httpx.ConnectError("b"), (200, b"win")]
    )
    transport = httpx.RetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=5
    )
    with httpx.Client(transport=transport) as client:
        response = client.get("https://example.com/mix")
    assert response.status_code == 200
    assert response.content == b"win"
    assert handler.calls == 4


def test_final_error_surfaces_after_mixed_sequence() -> None:
    handler = Scripted([(503, b""), httpx.ConnectError("x"), httpx.ConnectError("y")])
    transport = httpx.RetryTransport(
        transport=httpx.MockTransport(handler), max_attempts=3
    )
    with httpx.Client(transport=transport) as client:
        with pytest.raises(httpx.ConnectError):
            client.get("https://example.com/mix2")
    assert handler.calls == 3


def test_non_retryable_201_not_retried() -> None:
    handler = Scripted([(201, b"created")])
    with httpx.Client(
        transport=httpx.RetryTransport(
            transport=httpx.MockTransport(handler), max_attempts=3
        )
    ) as client:
        response = client.get("https://example.com/created")
    assert response.status_code == 201
    assert handler.calls == 1


def test_retryable_statuses_are_exactly_specified_set() -> None:
    retryable = {429, 500, 502, 503, 504}
    for status in list(range(400, 506)):
        handler = Scripted([(status, b"x"), (200, b"ok")])
        with httpx.Client(
            transport=httpx.RetryTransport(
                transport=httpx.MockTransport(handler), max_attempts=2
            )
        ) as client:
            response = client.get(f"https://example.com/{status}")
        if status in retryable:
            assert handler.calls == 2, f"{status} should retry but did not"
            assert response.status_code == 200
        else:
            assert handler.calls == 1, f"{status} must NOT be retried"
            assert response.status_code == status