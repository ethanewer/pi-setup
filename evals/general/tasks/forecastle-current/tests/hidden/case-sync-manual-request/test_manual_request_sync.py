"""Hidden case (sync): the client-level timeout must apply to manually
constructed httpx.Request instances handed to Client.send(), while an
explicit request-level timeout keeps winning. The upstream regression test
covers only the async path with a uvicorn server; this case exercises the
sync path against a plain standard-library server with different endpoints,
timeouts and repeated sends."""
import http.server
import socketserver
import threading

import pytest

import httpx

SLOW_DELAY = 0.5
MEDIUM_DELAY = 0.15


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def do_GET(self):
        path = self.path
        if path == "/slow":
            import time
            time.sleep(SLOW_DELAY)
        elif path == "/medium":
            import time
            time.sleep(MEDIUM_DELAY)
        body = b'{"ok": true}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


@pytest.fixture(scope="module")
def server_url():
    server = socketserver.TCPServer(("127.0.0.1", 0), Handler)
    server.allow_reuse_address = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = "http://127.0.0.1:%d" % server.server_address[1]
    yield url
    server.shutdown()
    server.server_close()


def test_client_timeout_applies_to_manual_request(server_url):
    """A hand-built request with no timeout of its own must be bounded by the
    client's timeout: a slow endpoint must raise, not succeed."""
    request = httpx.Request("GET", server_url + "/slow")
    with httpx.Client(timeout=0.1) as client:
        with pytest.raises(httpx.TimeoutException):
            client.send(request)


def test_request_level_small_timeout_wins(server_url):
    """An explicit request-level timeout smaller than the client's must win."""
    request = httpx.Request(
        "GET",
        server_url + "/slow",
        extensions={"timeout": httpx.Timeout(0.1).as_dict()},
    )
    with httpx.Client(timeout=30) as client:
        with pytest.raises(httpx.TimeoutException):
            client.send(request)


def test_request_level_large_timeout_wins(server_url):
    """An explicit request-level timeout larger than the client's must also
    win: the request is governed by its own timeout, not the client's."""
    request = httpx.Request(
        "GET",
        server_url + "/medium",
        extensions={"timeout": httpx.Timeout(30).as_dict()},
    )
    with httpx.Client(timeout=0.05) as client:
        response = client.send(request)
    assert response.status_code == 200


def test_repeated_sends_same_request_object(server_url):
    """Sending the same hand-built Request object several times through a
    short-timeout client must keep honouring the client timeout on every
    send (the fix must not be a one-shot state mutation)."""
    request = httpx.Request("GET", server_url + "/slow")
    with httpx.Client(timeout=0.1) as client:
        for _ in range(2):
            with pytest.raises(httpx.TimeoutException):
                client.send(request)


def test_default_timeout_client_still_succeeds_on_slowish_path(server_url):
    """A client using the library's default timeout must keep succeeding on
    a sub-second endpoint: the fix must not silently shorten the default for
    manually built requests (e.g. by redefining the default timeout value)."""
    request = httpx.Request("GET", server_url + "/medium")
    with httpx.Client() as client:
        response = client.send(request)
    assert response.status_code == 200


def test_fast_manual_request_succeeds_with_custom_header(server_url):
    """Unrelated behaviour must keep working: a hand-built request to a fast
    endpoint succeeds and carries its headers through."""
    request = httpx.Request(
        "GET", server_url + "/fast", headers={"X-Probe": "forecastle"}
    )
    with httpx.Client(timeout=10) as client:
        response = client.send(request)
    assert response.status_code == 200
    assert response.json() == {"ok": True}