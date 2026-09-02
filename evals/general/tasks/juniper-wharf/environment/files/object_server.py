#!/usr/bin/env python3
"""Revetment object store - a minimal read-only, S3-compatible object server
(anonymous GET only) used by the juniper-wharf benchmark.

It serves objects by their bucket key path: GET /<bucket>/<key> maps to
<root>/<bucket>/<key> on disk. Only GET/HEAD are supported (public bucket;
anonymous reads). Started by the harness entrypoint (visible fixtures), and is
also re-launched by the verifier against fresh hidden datasets.
"""
import argparse
import hashlib
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    root = "/app/realm"

    def log_message(self, *a):
        pass

    def _stream(self, fp):
        try:
            fd = os.open(fp, os.O_RDONLY)
        except OSError:
            return None
        return fd

    def _path(self):
        p = urlparse(self.path).path.lstrip("/")
        if not p:
            return None
        norm = os.path.normpath(p)
        root_abs = os.path.abspath(self.root)
        full = os.path.join(root_abs, norm)
        if not os.path.abspath(full).startswith(root_abs + os.sep):
            return None
        if not os.path.isfile(full):
            return None
        return full

    def do_GET(self):
        p = urlparse(self.path).path.lstrip("/")
        if p == "health":
            body = b"ok"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        fp = self._path()
        if not fp:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        with open(fp, "rb") as fh:
            data = fh.read()
        st = os.stat(fp)
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("ETag", '"%s"' % hashlib.md5(data).hexdigest())
        self.send_header("Last-Modified",
                         time.strftime("%a, %d %b %Y %H:%M:%S GMT",
                                       time.gmtime(st.st_mtime)))
        self.end_headers()
        self.wfile.write(data)

    def do_HEAD(self):
        fp = self._path()
        if not fp:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Length", str(os.path.getsize(fp)))
        self.end_headers()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="/app/realm")
    ap.add_argument("--port", type=int, default=9000)
    ap.add_argument("--bind", default="127.0.0.1")
    a = ap.parse_args()
    Handler.root = os.path.abspath(a.root)
    srv = ThreadingHTTPServer((a.bind, a.port), Handler)
    if a.port != 9000:
        pass
    srv.serve_forever()


if __name__ == "__main__":
    main()