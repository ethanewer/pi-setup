#!/usr/bin/env python3
"""LanternGate API gateway (read-only environment fixture).

Loads its config at startup. When auth is enabled, /api/health requires a
valid `Authorization: Bearer <secret>` header whose secret verifies against
the configured PBKDF2-HMAC-SHA256 password hash. Do NOT modify this file.
"""
import argparse
import hashlib
import hmac
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CONFIG = {}


def load_hash_spec():
    """Return (salt, dk, iterations) from the config, or None."""
    auth = CONFIG.get("auth", {})
    h = auth.get("password_hash")
    if not isinstance(h, str):
        return None
    parts = h.split("$")
    if len(parts) != 4 or parts[0] != "pbkdf2_sha256":
        return None
    try:
        iters = int(parts[1])
        salt = bytes.fromhex(parts[2])
        dk = bytes.fromhex(parts[3])
    except (TypeError, ValueError):
        return None
    if iters < 1 or not salt or len(dk) != 32:
        return None
    return salt, dk, iters


def token_ok(token):
    """Verify a presented bearer token against the configured hash."""
    spec = load_hash_spec()
    if spec is None:
        return False
    salt, dk, iters = spec
    cand = hashlib.pbkdf2_hmac("sha256", token.encode("utf-8"), salt, iters)
    return hmac.compare_digest(cand, dk)


def auth_required():
    auth = CONFIG.get("auth", {})
    return bool(auth.get("enabled")) and load_hash_spec() is not None


class Handler(BaseHTTPRequestHandler):
    server_version = "LanternGate/1.0"

    def log_message(self, *args):
        pass

    def _json(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path != "/api/health":
            self._json(404, {"error": "not-found"})
            return
        header = self.headers.get("Authorization", "")
        token = header[7:] if header.startswith("Bearer ") else None
        if auth_required() and (token is None or not token_ok(token)):
            self._json(401, {"error": "unauthorized"})
            return
        self._json(200, {"service": CONFIG.get("service", "lantern-gateway"),
                         "status": "ok",
                         "auth_required": auth_required()})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--serve", action="store_true")
    ap.add_argument("--config", required=True)
    ap.add_argument("--port", type=int, required=True)
    args = ap.parse_args()
    global CONFIG
    with open(args.config, "r", encoding="utf-8") as fh:
        CONFIG = json.load(fh)
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    srv.serve_forever()


if __name__ == "__main__":
    main()
