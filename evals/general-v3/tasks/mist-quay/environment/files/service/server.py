#!/usr/bin/env python3
"""MistQuay tide-relay service (fixture -- do not modify).

Serves GET / on 127.0.0.1. When [auth] enabled = true in config.ini, requests
must carry HTTP Basic credentials matching an entry in users.htpasswd (format
`user:$6$salthash`, SHA-512 crypt). Otherwise every request returns
`auth-disabled`.
"""
import base64
import configparser
import crypt
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

BASE = os.path.dirname(os.path.abspath(__file__))
HTPASSWD = os.path.join(BASE, "users.htpasswd")


def load_entries(path=None):
    entries = {}
    path = path or HTPASSWD
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or ":" not in line:
                    continue
                user, _, h = line.partition(":")
                entries[user] = h
    return entries


def check_password(user, password, entries=None):
    entries = load_entries() if entries is None else entries
    h = entries.get(user)
    if not h:
        return False
    try:
        return crypt.crypt(password, h) == h
    except Exception:
        return False


def auth_enabled(cfgpath=None):
    cfg = configparser.ConfigParser()
    cfg.read(cfgpath or os.path.join(BASE, "config.ini"))
    return cfg.get("auth", "enabled", fallback="false").strip().lower() == "true"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if not auth_enabled():
            body = b"auth-disabled\n"
            self.send_response(200)
        else:
            header = self.headers.get("Authorization", "")
            ok = False
            if header.startswith("Basic "):
                try:
                    raw = base64.b64decode(header[6:].strip()).decode("utf-8")
                    user, _, pw = raw.partition(":")
                    ok = check_password(user, pw)
                except Exception:
                    ok = False
            if ok:
                body = b"cove-ok\n"
                self.send_response(200)
            else:
                body = b"unauthorized\n"
                self.send_response(401)
                self.send_header("WWW-Authenticate", 'Basic realm="MistQuay"')
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def main():
    cfg = configparser.ConfigParser()
    cfg.read(os.path.join(BASE, "config.ini"))
    port = cfg.getint("service", "port", fallback=8731)
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
