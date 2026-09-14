"""Hidden case 3 (midships-spinnaker): offline, prepare-level check with a
LAZILY initialised attribute-forwarding proxy (the wrapped stream is created on
first attribute access). No server is involved: request preparation itself must
recognize the wrapper as a streaming body and pass it through untouched, with
the content preserved.
"""
import io

import requests


class LazyProxy:
    """A lazy file proxy: the wrapped stream is created on first use."""

    def __init__(self):
        self._stream = None

    def __getattr__(self, name):
        if self._stream is None:
            self._stream = io.BytesIO(b"lazy-hidden-case-payload")
        return getattr(self._stream, name)


def test_lazy_proxy_recognized_as_streaming_body():
    body = LazyProxy()
    req = requests.Request("POST", "http://example.invalid/post", data=body)
    prepared = req.prepare()
    # The wrapper must have been classified as a stream and passed through
    # untouched (not form-encoded or consumed).
    assert prepared.body is body
    assert body._stream is not None
    assert body._stream.getvalue() == b"lazy-hidden-case-payload"
    # And the body must still be a readable stream at send time.
    assert prepared.body._stream.read() == b"lazy-hidden-case-payload"