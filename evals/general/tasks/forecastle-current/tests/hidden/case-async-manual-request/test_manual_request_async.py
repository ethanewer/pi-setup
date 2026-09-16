"""Hidden case (async): the client-level timeout must apply to manually
constructed httpx.Request instances handed to AsyncClient.send(), under both
anyio backends, with request-level timeouts still winning. The upstream
regression test covers only the async path via the uvicorn fixture; this
case uses a plain standard-library server and additional inputs (per-request
overrides in both directions, a fast path, custom headers)."""
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


@pytest.mark.anyio
async def test_async_client_timeout_applies_to_manual_request(server_url):
    request = httpx.Request("GET", server_url + "/slow")
    async with httpx.AsyncClient(timeout=0.1) as client:
        with pytest.raises(httpx.TimeoutException):
            await client.send(request)


@pytest.mark.anyio
async def test_async_request_level_small_timeout_wins(server_url):
    request = httpx.Request(
        "GET",
        server_url + "/slow",
        extensions={"timeout": httpx.Timeout(0.1).as_dict()},
    )
    async with httpx.AsyncClient(timeout=30) as client:
        with pytest.raises(httpx.TimeoutException):
            await client.send(request)


@pytest.mark.anyio
async def test_async_request_level_large_timeout_wins(server_url):
    request = httpx.Request(
        "GET",
        server_url + "/medium",
        extensions={"timeout": httpx.Timeout(30).as_dict()},
    )
    async with httpx.AsyncClient(timeout=0.05) as client:
        response = await client.send(request)
    assert response.status_code == 200


@pytest.mark.anyio
async def test_async_repeated_sends_same_request_object(server_url):
    request = httpx.Request("GET", server_url + "/slow")
    async with httpx.AsyncClient(timeout=0.1) as client:
        for _ in range(2):
            with pytest.raises(httpx.TimeoutException):
                await client.send(request)


@pytest.mark.anyio
async def test_async_default_timeout_client_still_succeeds(server_url):
    """A client using the library's default timeout must keep succeeding on a
    sub-second endpoint (see the sync counterpart: defends against a fix that
    silently shortens the default for manually built requests)."""
    request = httpx.Request("GET", server_url + "/medium")
    async with httpx.AsyncClient() as client:
        response = await client.send(request)
    assert response.status_code == 200


@pytest.mark.anyio
async def test_async_fast_request_succeeds_with_custom_header(server_url):
    request = httpx.Request(
        "GET", server_url + "/fast", headers={"X-Probe": "forecastle"}
    )
    async with httpx.AsyncClient(timeout=10) as client:
        response = await client.send(request)
    assert response.status_code == 200
    assert response.json() == {"ok": True}