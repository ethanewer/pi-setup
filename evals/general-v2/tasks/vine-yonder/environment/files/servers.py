#!/usr/bin/env python3
"""Orchard platform mock stack: one process, two listeners.

Main listener (MOCK_PORT, default 9000) serves:
    GET /page                     -> the platform status page (fetch target)
    GET /hub/<ds>/manifest.json   -> dataset manifest
    GET /hub/<ds>/readme.md       -> dataset readme
    GET /hub/<ds>/<cfg>/<split>.csv -> dataset rows
    GET /rpc/status               -> chain node status
    GET /rpc/block/latest | /rpc/block/<n>
    GET /rpc/tx/<hash>
    GET /rpc/account/<addr>

Proxy listener (MOCK_PROXY_PORT, default 8055) very deliberately behaves like a
BROKEN forward proxy: every request is answered with a 502 "proxy error" page.
This is the override the outbound fetch tool is pointed at, so any fetch routed
through it irretrievably lands on the error page instead of the real /page.
"""
import os, json, re, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DATA = os.environ.get("MOCK_DATA_DIR", "/app/mockdata")
PAGE_PATH = os.path.join(DATA, "page.html")
CHAIN_PATH = os.path.join(DATA, "chain", "chain.json")
DATASETS_BASE = os.path.join(DATA, "datasets")


def _chain():
    with open(CHAIN_PATH) as f:
        return json.load(f)


class MainHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _send(self, code, ctype, data):
        body = data if isinstance(data, bytes) else data.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except Exception:
            pass

    def do_GET(self):
        p = self.path.split("?", 1)[0]
        try:
            if p == "/page":
                with open(PAGE_PATH, "rb") as f:
                    self._send(200, "text/html", f.read())
                return
            if p.startswith("/hub/") or p.startswith("/dataset/"):
                segs = p.lstrip("/").split("/")
                # /hub/<dataset>/<rest...>
                if segs[0] == "dataset":
                    segs = segs[1:]
                if len(segs) < 2:
                    self._send(404, "text/plain", "no hub resource")
                    return
                ds, rest = segs[1], segs[2:]
                base = os.path.realpath(os.path.join(DATASETS_BASE, ds))
                if not base.startswith(os.path.realpath(DATASETS_BASE)):
                    self._send(403, "text/plain", "forbidden")
                    return
                rel = os.path.join(*rest) if rest else ""
                fp = os.path.realpath(os.path.join(base, rel))
                if not fp.startswith(base) or not os.path.isfile(fp):
                    self._send(404, "text/plain", "no such file")
                    return
                if fp.endswith(".json"):
                    self._send(200, "application/json", open(fp, "rb").read())
                else:
                    self._send(200, "text/plain", open(fp, "rb").read())
                return
            if p.startswith("/rpc"):
                self._rpc(p.split("/rpc", 1)[1])
                return
            self._send(404, "text/plain", "not found")
        except Exception as e:
            self._send(500, "text/plain", "err %s" % e)

    def _rpc(self, path):
        c = _chain()
        parts = [x for x in path.split("/") if x]
        if not parts:
            self._send(404, "application/json", json.dumps({}))
            return
        cmd = parts[0]
        if cmd == "status":
            self._send(200, "application/json", json.dumps(c["node"]))
            return
        if cmd == "block" and parts[1:] == ["latest"]:
            b = c["blocks"][str(c["node"]["height"])]
            self._send(200, "application/json", json.dumps(b))
            return
        if cmd == "block":
            blk = c["blocks"].get(parts[1])
            self._send(200, "application/json",
                       json.dumps(blk if blk else {"error": "unknown block"}))
            return
        if cmd == "tx":
            want = parts[1] if len(parts) > 1 else ""
            for b in c["blocks"].values():
                for t in b.get("txs", []):
                    if t["hash"] == want:
                        self._send(200, "application/json",
                                   json.dumps(dict(t, blockNumber=b["number"])))
                        return
            self._send(200, "application/json",
                       json.dumps({"error": "unknown tx", "hash": want}))
            return
        if cmd == "account":
            addr = parts[1] if len(parts) > 1 else ""
            a = c["accounts"].get(addr)
            if not a:
                self._send(200, "application/json",
                           json.dumps({"error": "unknown account", "address": addr}))
                return
            rep = dict(a, address=addr)
            self._send(200, "application/json", json.dumps(rep))
            return
        self._send(404, "application/json", json.dumps({"error": "bad rpc"}))


class ProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def do_any(self):
        body = ("<html><body><h1>502 Bad Gateway (proxy error)</h1>"
                "<p>The egress proxy declared the upstream request failed. "
                "A fetch that reaches this page is broken.</p></body></html>"
                ).encode()
        self.send_response(502)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except Exception:
            pass

    do_GET = do_any
    do_POST = do_any
    do_PUT = do_any


def run(port, handler):
    srv = ThreadingHTTPServer(("0.0.0.0", port), handler)
    srv.serve_forever()


def main():
    port = int(os.environ.get("MOCK_PORT", "9000"))
    proxy_port = int(os.environ.get("MOCK_PROXY_PORT", "8051"))
    threads = []
    for p, h in ((port, MainHandler), (proxy_port, ProxyHandler)):
        t = threading.Thread(target=run, args=(p, h), daemon=True)
        t.start()
        threads.append(t)
    sys.stderr.write("mock stack on :%d proxy :%d data=%s\n"
                     % (port, proxy_port, DATA))
    while True:
        for t in threads:
            if not t.is_alive():
                raise SystemExit("listener died")
        import time
        time.sleep(1)


if __name__ == "__main__":
    main()