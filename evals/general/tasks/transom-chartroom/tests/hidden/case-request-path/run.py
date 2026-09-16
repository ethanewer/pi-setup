#!/usr/bin/env python3
"""Hidden case: full request-preparation path against a local HTTP server.

The upstream regression test drives requests.get() against httpbin with str
headers. This case uses the same prepared-request path with different inputs:
a name ending in a newline through requests.PreparedRequest.prepare(), and a
value ending in a newline through requests.get() against a local stdlib HTTP
server, asserting the InvalidHeader is raised before any bytes are sent and
that a valid request to the same server still succeeds.
"""
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import requests
from requests.exceptions import InvalidHeader


class Handler(BaseHTTPRequestHandler):
    received = 0

    def do_GET(self):  # noqa: N802
        type(self).received += 1
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *args):  # silence
        pass


def main() -> int:
    problems = []
    server = HTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    url = f"http://127.0.0.1:{port}/get"

    # 1) value ending in newline through the full get() path: must raise
    #    InvalidHeader and never reach the server.
    try:
        requests.get(url, headers={"foo": "bar\n"}, timeout=10)
        problems.append(
            "BUG: requests.get() with header value 'bar\\n' did not raise InvalidHeader"
        )
    except InvalidHeader:
        pass
    except Exception as exc:  # noqa: BLE001
        problems.append(f"expected InvalidHeader, got {type(exc).__name__}: {exc}")
    if Handler.received != 0:
        problems.append(
            f"malformed request reached the server ({Handler.received} request(s))"
        )

    # 2) name ending in newline through PreparedRequest.prepare(): must raise.
    try:
        prepared = requests.PreparedRequest()
        prepared.prepare(method="GET", url=url, headers={"foo\n": "bar"})
        problems.append(
            "BUG: PreparedRequest with header name 'foo\\n' did not raise InvalidHeader"
        )
    except InvalidHeader:
        pass
    except Exception as exc:  # noqa: BLE001
        problems.append(f"expected InvalidHeader, got {type(exc).__name__}: {exc}")

    # 3) a valid request to the same server must still succeed.
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()
    try:
        try:
            resp = requests.get(url, headers={"foo": "bar"}, timeout=10)
            if resp.status_code != 200 or Handler.received != 1:
                problems.append(
                    f"valid request failed: status={resp.status_code} "
                    f"received={Handler.received}"
                )
        except Exception as exc:  # noqa: BLE001
            problems.append(f"valid request raised {type(exc).__name__}: {exc}")
    finally:
        server.shutdown()
        server.server_close()

    if problems:
        for problem in problems:
            print(problem, file=sys.stderr)
        print("HIDDEN CASE REQUEST PATH: FAILED", file=sys.stderr)
        return 1
    print("HIDDEN CASE REQUEST PATH: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())