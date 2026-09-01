#!/usr/bin/env python3
"""Skiff landing toll gateway.

Reads /app/credentials.json at startup. Schema:

    {
      "enabled": <bool>,                 # password-based authentication on/off
      "users": {
        "<user>": {"algo": "sha512_crypt", "hash": "<sha512-crypt hash>"}
      }
    }

Routes:
  GET /health       -> 200 {"status": "ok"} (never requires auth)
  GET /toll?gate=X  -> 200 only when "enabled" is true and the HTTP Basic
                       credentials verify (crypt) against the stored hash;
                       403 when auth is disabled; 401 otherwise.
"""
import base64
import json
import sys
from crypt import crypt
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

CREDS_PATH = "/app/credentials.json"


def load_creds():
    with open(CREDS_PATH, "r", encoding="utf-8") as fh:
        return json.load(fh)


CREDS = load_creds()


def check_credentials(user, secret):
    try:
        rec = CREDS["users"][user]
    except (KeyError, TypeError):
        return False
    if not isinstance(rec, dict) or rec.get("algo") != "sha512_crypt":
        return False
    stored = rec.get("hash")
    if not isinstance(stored, str) or not stored.startswith("$6$"):
        return False  # missing or locked ("!") entries never verify
    try:
        return crypt(secret, stored) == stored
    except OSError:
        return False


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/health":
            return self._send(200, {"status": "ok"})
        if url.path == "/toll":
            if CREDS.get("enabled") is not True:
                return self._send(403, {"status": "auth-disabled"})
            auth = self.headers.get("Authorization", "")
            if not auth.startswith("Basic "):
                return self._send(401, {"status": "unauthorized"})
            try:
                raw = base64.b64decode(auth[6:].strip()).decode("utf-8")
                user, _, secret = raw.partition(":")
            except Exception:
                return self._send(401, {"status": "unauthorized"})
            if check_credentials(user, secret):
                gate = (parse_qs(url.query).get("gate") or [""])[0]
                return self._send(200, {"status": "ok", "user": user, "gate": gate})
            return self._send(401, {"status": "unauthorized"})
        return self._send(404, {"status": "not-found"})

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8642
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
