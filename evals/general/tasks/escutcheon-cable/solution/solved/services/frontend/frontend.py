#!/usr/bin/env python3
"""Cart front storefront (www) — traced.

The public edge of the system: accepts client requests, fans out to the Go
backend for order data, returns JSON. Implements the repository README
observability contract: accepts/propagates W3C traceparent, writes structured
JSON logs (correlation field `trace_id`) to stdout (redirected by up.sh to
.logs/frontend.jsonl), and emits one span per handled request to the
collector at 127.0.0.1:9100/span.
"""
import json
import re
import secrets
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FRONT_HOST = "127.0.0.1"
FRONT_PORT = 8000
BACK = "http://127.0.0.1:8100"
COLLECTOR = "http://127.0.0.1:9100/span"

_HEX = re.compile(r"^[0-9a-fA-F]+$")
ZERO16 = "0000000000000000"
ZERO32 = "00000000000000000000000000000000"


def parse_traceparent(header):
    """Return (trace_id, parent_span_id) or (None, None)."""
    if not header:
        return None, None
    parts = header.split("-")
    if (len(parts) == 4 and parts[0] == "00"
            and len(parts[1]) == 32 and len(parts[2]) == 16
            and len(parts[3]) == 2
            and bool(_HEX.match(parts[1])) and bool(_HEX.match(parts[2]))):
        return parts[1].lower(), parts[2].lower()
    return None, None


def new_trace_id():
    return secrets.token_hex(16)      # 32 lower-hex


def new_span_id():
    return secrets.token_hex(8)       # 16 lower-hex


def emit_span(rec):
    try:
        req = urllib.request.Request(
            COLLECTOR, data=json.dumps(rec).encode(),
            headers={"Content-Type": "application/json"}, method="POST")
        urllib.request.urlopen(req, timeout=2).read()
    except Exception as exc:
        log_line(level="warn", msg="span_emit_failed", err=str(exc))


def jlog(**kw):
    base = {"ts": int(time.time() * 1000), "service": "frontend",
            "level": "info", "trace_id": ZERO32, "span_id": ZERO16}
    base.update(kw)
    print(json.dumps(base, sort_keys=True), flush=True)


def call_back(order_id, trace_id, span_id):
    """Call the backend, propagating the same trace id. Returns (status, body)."""
    req = urllib.request.Request(
        BACK + "/order/" + order_id,
        headers={"traceparent": "00-%s-%s-01" % (trace_id, span_id)})
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:      # backend answered 4xx/5xx
        return e.code, e.read()
    except Exception:
        return 502, json.dumps({"error": "backend_unreachable"}).encode()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _reply(self, code, body):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _ctx(self):
        trace_id, parent = parse_traceparent(self.headers.get("traceparent"))
        if trace_id is None:
            trace_id = new_trace_id()
        return trace_id, parent or ZERO16

    def do_GET(self):
        path = re.sub(r"\?.*$", "", self.path)
        if path == "/health":
            jlog(msg="health")
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
        trace_id, parent = self._ctx()
        span_id = new_span_id()
        start = time.time()
        jlog(trace_id=trace_id, span_id=span_id, parent_span_id=parent,
             msg="order.request", order_id=order_id, route="/order/" + order_id)
        status, body = call_back(order_id, trace_id, span_id)
        self._finish_span(trace_id, span_id, parent, "frontend.order",
                          status, int(start * 1000))
        jlog(trace_id=trace_id, span_id=span_id,
             msg="order.complete", order_id=order_id, status=status,
             duration_ms=int((time.time() - start) * 1000))
        self._reply(status, body)

    def _batch(self, a, b):
        trace_id, parent = self._ctx()
        span_id = new_span_id()
        start = time.time()
        jlog(trace_id=trace_id, span_id=span_id, parent_span_id=parent,
             msg="batch.request", ids=[a, b], route="/batch/%s/%s" % (a, b))
        with ThreadPoolExecutor(max_workers=2) as ex:
            futs = [ex.submit(call_back, oid, trace_id, span_id) for oid in (a, b)]
            results = [f.result() for f in futs]
        if any(s >= 500 for s, _ in results):
            fail = next(root_status(s) for s, _ in results if s >= 500)
            self._finish_span(trace_id, span_id, parent, "frontend.batch",
                              fail, int(start * 1000))
            jlog(trace_id=trace_id, span_id=span_id, msg="batch.failed",
                 ids=[a, b], status=fail)
            self._reply(fail, json.dumps({"error": "batch_failed"}))
            return
        payload = [json.loads(b) for _, b in results]
        self._finish_span(trace_id, span_id, parent, "frontend.batch",
                          200, int(start * 1000))
        jlog(trace_id=trace_id, span_id=span_id, msg="batch.complete",
             ids=[a, b], status=200,
             duration_ms=int((time.time() - start) * 1000))
        self._reply(200, json.dumps(payload))

    def _finish_span(self, trace_id, span_id, parent, name, status, start_ms):
        emit_span({
            "service": "frontend", "name": name,
            "trace_id": trace_id, "span_id": span_id,
            "parent_span_id": parent, "kind": "server",
            "start_ms": start_ms, "end_ms": int(time.time() * 1000),
            "status": status, "error": status >= 500,
        })


def root_status(status):
    return status


if __name__ == "__main__":
    print("frontend on %s:%s" % (FRONT_HOST, FRONT_PORT), flush=True)
    ThreadingHTTPServer((FRONT_HOST, FRONT_PORT), Handler).serve_forever()
