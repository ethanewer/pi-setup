#!/usr/bin/env python3
"""Cirque object store — a minimal read-only, S3-style object server used by
the drift-quarry benchmark.

Serves objects by bucket key: GET /<bucket>/<key> maps to <root>/<bucket>/<key>
on disk. Only GET/HEAD are supported (public bucket, anonymous reads). Started
by the harness entrypoint for the visible fixtures, and re-launched by the
verifier against fresh hidden stores.
"""
import argparse
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    root = "/app/realm"

    def log_message(self, *a):
        pass

    def _resolve(self):
        p = urlparse(self.path).path.lstrip("/")
        if not p or p == "health":
            return None
        norm = os.path.normpath(p)
        if norm.startswith(".."):
            return None
        root_abs = os.path.realpath(self.root)
        full = os.path.realpath(os.path.join(root_abs, norm))
        if not full.startswith(root_abs + os.sep):
            return None
        if not os.path.isfile(full):
            return None
        return full

    def _serve(self, body_only_headers=False):
        fp = self._resolve()
        if fp is None:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        size = os.path.getsize(fp)
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(size))
        self.end_headers()
        if not body_only_headers:
            with open(fp, "rb") as fh:
                while True:
                    chunk = fh.read(65536)
                    if not chunk:
                        break
                    self.wfile.write(chunk)

    def do_GET(self):
        p = urlparse(self.path).path
        if p == "/health":
            body = b"ok"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self._serve()

    def do_HEAD(self):
        p = urlparse(self.path).path
        if p == "/health":
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.end_headers()
            return
        self._serve(body_only_headers=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--bind", default="127.0.0.1")
    args = ap.parse_args()
    Handler.root = args.root
    srv = ThreadingHTTPServer((args.bind, args.port), Handler)
    srv.serve_forever()


if __name__ == "__main__":
    main()
