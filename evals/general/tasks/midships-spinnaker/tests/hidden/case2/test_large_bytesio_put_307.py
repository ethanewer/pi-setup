"""Hidden case 2 (midships-spinnaker): a large (multi-chunk) payload delivered
through an attribute-forwarding wrapper over an in-memory stream, sent with
PUT and followed through a 307 redirect. Exercises repeated read() calls on the
wrapper and the redirect re-post of a large body.
"""
import io
from pathlib import Path

import pytest
import requests
from requests.compat import urljoin


@pytest.fixture(scope="module")
def httpbin_url(httpbin):
    base = httpbin.url.rstrip("/") + "/"

    def inner(*suffix):
        return urljoin(base, "/".join(suffix))

    return inner


class BytesIOProxy:
    """Forwards every attribute lookup to a wrapped BytesIO."""

    def __init__(self, stream):
        self._stream = stream

    def __getattr__(self, name):
        return getattr(self._stream, name)


def test_large_bytesio_proxy_put_through_307(httpbin_url):
    payload = (Path(__file__).with_name("payload.txt")).read_bytes()
    body = BytesIOProxy(io.BytesIO(payload))
    r = requests.put(httpbin_url("redirect-to?url=/put&status_code=307"), data=body)
    assert r.status_code == 200, r.text
    assert len(r.history) >= 1, "expected a 307 redirect to have been followed"
    assert r.json()["data"] == payload.decode("utf-8")
    assert len(payload) > 65536, "payload should span multiple reads"