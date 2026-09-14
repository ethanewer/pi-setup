#!/usr/bin/env python3
"""forecastle-current reproduction script.

Demonstrates that the per-client timeout is silently ignored when a request
is built by hand as an httpx.Request and handed to Client.send(): the send
then waits for the library's default timeout instead of the client's
configured one, and eventually succeeds.

Output contract (see the task instruction):
  * prints a line starting with "OK" and exits 0 when the client timeout was
    honoured (httpx.TimeoutException raised quickly);
  * prints a line starting with "BUG" and exits nonzero when the timeout was
    ignored (the send returned a response).

Self-contained: standard library + httpx only.
"""
import http.server
import socketserver
import threading
import time

import httpx

DELAY = 0.25
CLIENT_TIMEOUT = 0.05


class SlowHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        time.sleep(DELAY)
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *_args):
        pass


server = socketserver.TCPServer(("127.0.0.1", 0), SlowHandler)
threading.Thread(target=server.serve_forever, daemon=True).start()
url = "http://127.0.0.1:%d/" % server.server_address[1]

request = httpx.Request("GET", url)  # built by hand, no timeout of its own
client = httpx.Client(timeout=CLIENT_TIMEOUT)
start = time.time()
try:
    response = client.send(request)
except httpx.TimeoutException as exc:
    elapsed = time.time() - start
    print("OK timeout honoured: %s after %.3fs" % (type(exc).__name__, elapsed))
    raise SystemExit(0)
else:
    elapsed = time.time() - start
    print(
        "BUG send succeeded (status %s) after %.3fs although the client "
        "timeout is %.2fs -- the per-client timeout was ignored"
        % (response.status_code, elapsed, CLIENT_TIMEOUT)
    )
    raise SystemExit(1)