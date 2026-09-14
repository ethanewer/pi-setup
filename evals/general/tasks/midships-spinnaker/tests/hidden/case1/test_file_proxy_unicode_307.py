"""Hidden case 1 (midships-spinnaker): an attribute-forwarding wrapper over a
REAL open file, non-ASCII payload, POST followed by a 307 redirect. The body
must be recognized as a stream and re-posted intact after the redirect.
"""
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


class FileProxy:
    """Forwards every attribute lookup to a wrapped file object."""

    def __init__(self, f):
        self._f = f

    def __getattr__(self, name):
        return getattr(self._f, name)


def test_file_proxy_unicode_post_through_307(httpbin_url):
    payload_path = Path(__file__).with_name("payload.txt")
    payload_bytes = payload_path.read_bytes()
    payload = payload_bytes.decode("utf-8")
    with payload_path.open("rb") as f:
        body = FileProxy(f)
        r = requests.post(
            httpbin_url("redirect-to?url=/post&status_code=307"), data=body
        )
    assert r.status_code == 200, r.text
    assert len(r.history) >= 1, "expected a 307 redirect to have been followed"
    assert r.json()["data"] == payload