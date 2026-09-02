#!/usr/bin/env python3
"""Gryphon Relay media server.

Serves a directory tree over HTTP using only the standard library so the
ingest pipeline can fetch "remote" media from a local URL.

Usage:  python3 /app/serve_media.py <directory> <port>

- Binds to 127.0.0.1 on the given TCP port.
- Serves files under <directory> at "/" (no directory listing needed).
- Query strings on request URLs are ignored (SimpleHTTPRequestHandler).
- A path that does not exist returns HTTP 404.
"""
import http.server
import os
import sys
import functools


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def serve(directory: str, port: int) -> None:
    os.chdir(directory)
    handler = functools.partial(QuietHandler, directory=directory)
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    httpd.serve_forever()


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: serve_media.py <directory> <port>", file=sys.stderr)
        sys.exit(2)
    serve(os.path.abspath(sys.argv[1]), int(sys.argv[2]))
