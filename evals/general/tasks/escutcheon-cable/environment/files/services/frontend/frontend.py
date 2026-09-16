#!/usr/bin/env python3
"""Cart front storefront (www).

A small Python (stdlib-only) HTTP service that is the public edge of the
system: it receives client requests, fans out to the Go backend whenever a
request needs order data, and returns JSON to the client.

This is the SHIPPED baseline. It works end to end (orders resolve, errors
propagate) but it performs NO distributed tracing and emits only plain-text
log lines. See the repository README for the observability contract that this
service and the backend must satisfy.
"""
import json
import re
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FRONT_HOST = "127.0.0.1"
FRONT_PORT = 8000
BACK = "http://127.0.0.1:8100"


def call_back(order_id):
    """Hit the Go backend and return (status, body_bytes)."""
    req = urllib.request.Request(BACK + "/order/" + order_id)
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:      # backend answered 4xx/5xx
        return e.code, e.read()
    except Exception:
        return 502, json.dumps({"error": "backend_unreachable"}).encode()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):           # keep the server console quiet
        pass

    def _reply(self, code, body):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = re.sub(r"\?.*$", "", self.path)
        if path == "/health":
            print("frontend health " + self.address_string(), flush=True)
            self._reply(200, '{"ok":true}')
            return
        m = re.fullmatch(r"/order/([^/]+)", path)
        if m:
            self._order(m.group(1))
            return
        m = re.fullmatch(r"/batch/([^/]+)/([^/]+)", path)
        if m:
            self._batch(m.group(1), m.group(2))
            return
        self._reply(404, json.dumps({"error": "not_found"}))

    def _order(self, order_id):
        print("frontend order.render id=%s" % order_id, flush=True)
        status, body = call_back(order_id)
        self._reply(status, body)

    def _batch(self, a, b):
        print("frontend batch.render a=%s b=%s" % (a, b), flush=True)
        with ThreadPoolExecutor(max_workers=2) as ex:
            futs = [ex.submit(call_back, a), ex.submit(call_back, b)]
            results = [f.result() for f in futs]
        if any(s >= 500 for s, _ in results):
            fail = next((s for s, _ in results if s >= 500), 502)
            self._reply(fail, json.dumps({"error": "batch_failed"}))
            return
        payload = [json.loads(b) for _, b in results]
        self._reply(200, json.dumps(payload))


if __name__ == "__main__":
    print("frontend on %s:%s" % (FRONT_HOST, FRONT_PORT), flush=True)
    ThreadingHTTPServer((FRONT_HOST, FRONT_PORT), Handler).serve_forever()
