#!/usr/bin/env python3
"""Cart local span collector (sink).

A small Python HTTP service, complete as shipped, that the graded services
must export their W3C trace spans to. It accepts span records via POST, keeps
them in memory, and serves them back over GET so the grader can inspect the
collected trace tree.

Endpoints (all on 127.0.0.1:9100):
  POST /span           accept one span record (JSON)
  GET  /spans          all collected spans (JSON array)
  GET  /spans?trace=T  spans whose trace_id == T
  GET  /reset          clear the store
  GET  /health         200 ok
"""
import json
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST, PORT = "127.0.0.1", 9100
_lock = threading.Lock()
_spans = []


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code, payload, ctype="application/json"):
        if isinstance(payload, str):
            payload = payload.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        if url.path != "/span":
            self._send(404, '{"error":"not_found"}')
            return
        try:
            length = int(self.headers.get("Content-Length", 0) or 0)
            rec = json.loads(self.rfile.read(length) or b"{}")
            if not isinstance(rec, dict):
                raise ValueError("span must be a JSON object")
        except Exception:
            self._send(400, '{"error":"bad_span"}')
            return
        rec.setdefault("received_ms", int(time.time() * 1000))
        with _lock:
            _spans.append(rec)
        self._send(200, '{"ok":true}')

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        if url.path == "/spans":
            qs = urllib.parse.parse_qs(url.query)
            trace = (qs.get("trace") or [None])[0]
            with _lock:
                items = [s for s in _spans
                         if not trace or s.get("trace_id") == trace]
            self._send(200, json.dumps(items))
        elif url.path == "/reset":
            with _lock:
                _spans.clear()
            self._send(200, '{"ok":true}')
        elif url.path == "/health":
            self._send(200, '{"ok":true}')
        else:
            self._send(404, '{"error":"not_found"}')


if __name__ == "__main__":
    print("collector on %s:%s" % (HOST, PORT), flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
