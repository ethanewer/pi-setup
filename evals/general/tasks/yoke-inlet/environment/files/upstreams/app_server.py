#!/usr/bin/env python3
"""Yoke-inlet upstream application server (shipped fixture).

The reverse proxy the agent configures balances traffic between two instances
of this server: a "canary" (port 8123) and a "stable" (port 8124). Both
instances serve identical content, so only the "server" field of the JSON
reveals which instance handled a request.

Run one instance per upstream, e.g.:

    python3 app_server.py --name canary --port 8123
    python3 app_server.py --name stable --port 8124

Endpoints:
    GET /healthz   -> {"status": "ok", "server": ..., "port": ...}
    GET <any path> -> {"server": ..., "port": ..., "path": ..., "query": ...}

Python 3 stdlib only; no third-party dependencies.
"""
import argparse
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

SELF = {"name": None, "port": None, "banner": "yoke"}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "YokeUpstream/1.0"

    def _reply(self, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/healthz":
            self._reply({
                "status": "ok",
                "server": SELF["name"],
                "port": SELF["port"],
                "banner": SELF["banner"],
            })
            return
        self._reply({
            "server": SELF["name"],
            "port": SELF["port"],
            "path": parsed.path,
            "query": parsed.query,
            "banner": SELF["banner"],
        })

    def do_HEAD(self):
        self.do_GET()

    def log_message(self, fmt, *args):
        sys.stderr.write("%s\n" % (fmt % args,))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--name", required=True, help="instance name, e.g. canary")
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--banner", default="yoke")
    args = ap.parse_args()
    SELF["name"] = args.name
    SELF["port"] = args.port
    SELF["banner"] = args.banner
    srv = ThreadingHTTPServer((args.bind, args.port), Handler)
    srv.daemon_threads = True
    print("listening on %s:%d" % (args.bind, args.port), file=sys.stderr)
    srv.serve_forever()


if __name__ == "__main__":
    main()