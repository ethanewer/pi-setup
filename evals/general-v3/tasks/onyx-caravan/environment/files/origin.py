#!/usr/bin/env python3
"""Depot-operations login origin: local HTTP service for session exercises.

Usage: python3 origin.py <config.json> <port>

The origin listens on 127.0.0.1:<port> and implements the documented
challenge / login / panel / logout protocol. It is deterministic: session ids
and CSRF tokens are derived from the config's sid_secret, and challenge
nonces from a per-process counter.
"""
import hashlib
import hmac
import json
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOCK = threading.Lock()


def csrf_for(sid):
    return hashlib.sha256((sid + ":csrf").encode()).hexdigest()[:16]


def sid_for(cfg, username):
    return hmac.new(
        cfg["sid_secret"].encode(), username.encode(), hashlib.sha256
    ).hexdigest()[:24]


def make_handler(cfg):
    state = {"counter": 0, "issued": set(), "sessions": {}}

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *args):
            pass

        def _send(self, code, obj, extra_headers=None):
            body = json.dumps(obj).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            for key, value in (extra_headers or []):
                self.send_header(key, value)
            self.end_headers()
            self.wfile.write(body)

        def _cookie_sid(self):
            raw = self.headers.get("Cookie", "") or ""
            for part in raw.split(";"):
                key, _, value = part.strip().partition("=")
                if key == cfg["cookie_name"]:
                    return value
            return None

        def _form(self):
            length = int(self.headers.get("Content-Length", 0) or 0)
            raw = self.rfile.read(length) if length else b""
            parsed = urllib.parse.parse_qs(raw.decode("utf-8", "replace"))

            def field(name):
                vals = parsed.get(name)
                return vals[0] if vals else None
            return field

        def do_GET(self):
            path = urllib.parse.urlparse(self.path).path
            if path == "/challenge":
                with LOCK:
                    state["counter"] += 1
                    n = state["counter"]
                    nonce = hashlib.sha256(
                        ("%s:%d" % (cfg["sid_secret"], n)).encode()
                    ).hexdigest()[:32]
                    state["issued"].add(nonce)
                self._send(200, {"nonce": nonce, "alg": cfg["challenge_alg"]})
            elif path == "/panel":
                sid = self._cookie_sid()
                with LOCK:
                    user = state["sessions"].get(sid)
                if user is None:
                    self._send(401, {"ok": False})
                else:
                    self._send(200, {"username": user, "csrf": csrf_for(sid)})
            else:
                self._send(404, {"ok": False})

        def do_POST(self):
            path = urllib.parse.urlparse(self.path).path
            field = self._form()
            if path == "/login":
                username = field("username")
                password = field("password")
                token = field("token")
                nonce = field("nonce")
                with LOCK:
                    unused = nonce in state["issued"]
                    state["issued"].discard(nonce)
                if not unused or username is None:
                    self._send(401, {"ok": False})
                    return
                user = next(
                    (u for u in cfg["users"] if u["username"] == username), None
                )
                ok = False
                if user and password == user["password"] and token:
                    expected = hashlib.new(
                        cfg["challenge_alg"],
                        (nonce + user["password"]).encode(),
                    ).hexdigest()
                    ok = hmac.compare_digest(expected, token)
                if ok and cfg.get("require_nonce_header"):
                    ok = self.headers.get("X-Nonce") == nonce
                if not ok:
                    self._send(401, {"ok": False})
                    return
                sid = sid_for(cfg, username)
                with LOCK:
                    state["sessions"][sid] = username
                cookie = "%s=%s; Path=/; HttpOnly" % (cfg["cookie_name"], sid)
                self._send(200, {"ok": True, "sid": sid},
                           [("Set-Cookie", cookie)])
            elif path == "/logout":
                sid = self._cookie_sid()
                with LOCK:
                    user = state["sessions"].get(sid)
                csrf = field("csrf")
                if (user is not None and csrf is not None
                        and hmac.compare_digest(csrf_for(sid), csrf)):
                    with LOCK:
                        del state["sessions"][sid]
                    self._send(200, {"ok": True, "logged_out": True})
                else:
                    self._send(401, {"ok": False})
            else:
                self._send(404, {"ok": False})

    return Handler


def main():
    if len(sys.argv) != 3:
        print("usage: origin.py <config.json> <port>", file=sys.stderr)
        return 2
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        cfg = json.load(fh)
    server = ThreadingHTTPServer(("127.0.0.1", int(sys.argv[2])), make_handler(cfg))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
