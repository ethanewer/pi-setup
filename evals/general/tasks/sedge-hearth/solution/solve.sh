#!/bin/bash
#
# sedge-hearth oracle.
# Writes the deliverable /app/token_service.py: an HMAC-signed JWT-style
# token auth service (claims, expiry, rotation, revocation blacklist)
# serving the documented API on 127.0.0.1:<config.port> via the read-only
# /app/lib/httpkit.py stub. Then starts it and smoke-tests the visible
# config end to end. The oracle never peeks at verifier internals.
set -euo pipefail

cat > /app/token_service.py <<'PY'
#!/usr/bin/env python3
"""Onyx Gate — HMAC-signed JWT-style token auth service (sedge-hearth).

Reads /app/config.json at startup and serves the documented API on
127.0.0.1:<config.port> using the read-only /app/lib/httpkit.py stub:

  POST /login   {"user","password"}            -> access+refresh pair
  POST /refresh {"refresh_token"}              -> rotated pair (old revoked)
  POST /logout  {"access_token"}               -> {"ok": true}
  GET  /me      Authorization: Bearer <tok>    -> the six claims
  GET  /health                                 -> {"status": "ok"}

Tokens are three unpadded base64url segments header.payload.signature with
HMAC-SHA256 over "<header>.<payload>" keyed by config["secret"]. Header is
exactly {"alg":"HS256","typ":"JWT"}; payload is compact JSON with keys in
the order sub, iss, iat, exp, jti, typ. Server time is the X-Onyx-Now header
when present (used as iat for mints and for all tolerance windows) with
clock_skew_sec tolerance. jti = "<nonce>-<seq:08x>": fresh 8-hex nonce per
process, seq = per-process minted-token counter from 0. Revocations persist
atomically to /app/state/blacklist.json and survive restarts.
"""
import base64
import hashlib
import hmac
import json
import os
import secrets
import sys
import threading
import time

sys.path.insert(0, "/app/lib")
from httpkit import HttpError, error, serve  # noqa: E402

CONFIG_PATH = "/app/config.json"
STATE_DIR = "/app/state"
BLACKLIST_PATH = os.path.join(STATE_DIR, "blacklist.json")

REQUIRED_CLAIMS = ("sub", "iss", "iat", "exp", "jti", "typ")
HEADER_EXACT = {"alg": "HS256", "typ": "JWT"}
REASONS = ("logout", "rotated")


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def b64url_dec(segment):
    padding = "=" * (-len(segment) % 4)
    return base64.b64decode(segment + padding, altchars=b"-_", validate=True)


def compact(obj):
    return json.dumps(obj, separators=(",", ":"))


class TokenService:
    def __init__(self, cfg):
        self.cfg = cfg
        self.secret = str(cfg["secret"]).encode("utf-8")
        self.issuer = str(cfg["issuer"])
        self.tolerance = int(cfg["clock_skew_sec"])
        self.life = {"access": int(cfg["lifetimes"]["access_sec"]),
                     "refresh": int(cfg["lifetimes"]["refresh_sec"])}
        self.users = cfg["users"]
        self.lock = threading.Lock()
        self.nonce = secrets.token_hex(4)   # fresh per process start
        self.seq = 0                        # minted-token counter
        self.blacklist = {}                 # jti -> {"reason": str}
        self._load_blacklist()

    # ------------------------------------------------------------------
    # blacklist persistence
    # ------------------------------------------------------------------
    def _load_blacklist(self):
        os.makedirs(STATE_DIR, exist_ok=True)
        if not os.path.exists(BLACKLIST_PATH):
            self.blacklist = {}
            return
        try:
            with open(BLACKLIST_PATH, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except Exception as exc:
            sys.stderr.write("onyx: blacklist.json unreadable: %s\n" % exc)
            sys.exit(1)
        if (not isinstance(data, dict) or not isinstance(data.get("entries"), dict)):
            sys.stderr.write("onyx: blacklist.json has an invalid shape\n")
            sys.exit(1)
        self.blacklist = data["entries"]

    def _persist_blacklist(self):
        tmp = BLACKLIST_PATH + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump({"version": 1, "entries": self.blacklist}, fh,
                      separators=(",", ":"))
        os.replace(tmp, BLACKLIST_PATH)

    def _revoke(self, jti, reason):
        self.blacklist[jti] = {"reason": reason}
        self._persist_blacklist()

    # ------------------------------------------------------------------
    # server time
    # ------------------------------------------------------------------
    def _now(self, req):
        raw = req.headers.get("x-onyx-now")
        if raw is None:
            return int(time.time())
        try:
            value = int(raw)
        except (TypeError, ValueError):
            raise HttpError(400, "bad_request", "invalid X-Onyx-Now")
        if value < 0:
            raise HttpError(400, "bad_request", "invalid X-Onyx-Now")
        return value

    # ------------------------------------------------------------------
    # minting / validation
    # ------------------------------------------------------------------
    def _mint(self, sub, typ, now):
        with self.lock:
            jti = "%s-%08x" % (self.nonce, self.seq)
            self.seq += 1
        header_b64 = b64url(compact(HEADER_EXACT).encode("utf-8"))
        payload_b64 = b64url(compact({
            "sub": sub, "iss": self.issuer, "iat": now,
            "exp": now + self.life[typ], "jti": jti, "typ": typ,
        }).encode("utf-8"))
        signature = b64url(hmac.new(
            self.secret, ("%s.%s" % (header_b64, payload_b64)).encode("ascii"),
            hashlib.sha256).digest())
        return "%s.%s.%s" % (header_b64, payload_b64, signature)

    def _parse_token(self, token, required_typ, req):
        if not isinstance(token, str):
            raise HttpError(401, "invalid_token", "token must be a string")
        parts = token.split(".")
        if len(parts) != 3:
            raise HttpError(401, "invalid_token", "token must have 3 segments")
        header_b64, payload_b64, sig_b64 = parts
        try:
            header = json.loads(b64url_dec(header_b64))
            payload = json.loads(b64url_dec(payload_b64))
        except Exception:
            raise HttpError(401, "invalid_token", "undecodable token segment")
        if not isinstance(header, dict) or not isinstance(payload, dict):
            raise HttpError(401, "invalid_token", "token segments must be objects")
        if header != HEADER_EXACT:
            raise HttpError(401, "invalid_token", "unsupported token header")
        for key in REQUIRED_CLAIMS:
            if key not in payload:
                raise HttpError(401, "invalid_token", "missing claim %s" % key)
        for key in ("sub", "iss", "jti", "typ"):
            if not isinstance(payload[key], str):
                raise HttpError(401, "invalid_token", "claim %s must be a string" % key)
        for key in ("iat", "exp"):
            if not isinstance(payload[key], int) or isinstance(payload[key], bool):
                raise HttpError(401, "invalid_token", "claim %s must be an integer" % key)
        expected = b64url(hmac.new(
            self.secret, ("%s.%s" % (header_b64, payload_b64)).encode("ascii"),
            hashlib.sha256).digest())
        if not hmac.compare_digest(expected.encode("ascii"), sig_b64.encode("ascii")):
            raise HttpError(401, "invalid_token", "signature mismatch")
        if payload["iss"] != self.issuer:
            raise HttpError(401, "invalid_token", "unknown issuer")
        if payload["typ"] != required_typ:
            raise HttpError(401, "invalid_token", "wrong token type")
        if payload["jti"] in self.blacklist:
            raise HttpError(401, "token_revoked", "token is revoked")
        now = self._now(req)
        if payload["iat"] > now + self.tolerance:
            raise HttpError(401, "token_not_yet_valid", "token is from the future")
        if payload["exp"] < now - self.tolerance:
            raise HttpError(401, "token_expired", "token has expired")
        return payload

    # ------------------------------------------------------------------
    # handlers
    # ------------------------------------------------------------------
    def handle_login(self, req):
        if req.method != "POST":
            raise HttpError(405, "method_not_allowed", "POST required")
        body = req.json()
        if not isinstance(body, dict) or "user" not in body or "password" not in body:
            raise HttpError(400, "bad_request", "user and password required")
        user, password = body["user"], body["password"]
        if not isinstance(user, str) or not isinstance(password, str):
            raise HttpError(400, "bad_request", "user and password must be strings")
        entry = self.users.get(user)
        if entry is None or entry.get("password") != password:
            raise HttpError(401, "invalid_credentials", "bad user or password")
        now = self._now(req)
        access = self._mint(user, "access", now)
        refresh = self._mint(user, "refresh", now)
        return {
            "access_token": access,
            "refresh_token": refresh,
            "token_type": "bearer",
            "access_expires_in": self.life["access"],
            "refresh_expires_in": self.life["refresh"],
        }

    def handle_refresh(self, req):
        if req.method != "POST":
            raise HttpError(405, "method_not_allowed", "POST required")
        body = req.json()
        if not isinstance(body, dict) or "refresh_token" not in body:
            raise HttpError(400, "bad_request", "refresh_token required")
        token = body["refresh_token"]
        if not isinstance(token, str):
            raise HttpError(400, "bad_request", "refresh_token must be a string")
        claims = self._parse_token(token, "refresh", req)
        with self.lock:
            self._revoke(claims["jti"], "rotated")
        now = self._now(req)
        sub = claims["sub"]
        access = self._mint(sub, "access", now)
        refresh = self._mint(sub, "refresh", now)
        return {
            "access_token": access,
            "refresh_token": refresh,
            "token_type": "bearer",
            "access_expires_in": self.life["access"],
            "refresh_expires_in": self.life["refresh"],
        }

    def handle_logout(self, req):
        if req.method != "POST":
            raise HttpError(405, "method_not_allowed", "POST required")
        body = req.json()
        if not isinstance(body, dict) or "access_token" not in body:
            raise HttpError(400, "bad_request", "access_token required")
        token = body["access_token"]
        if not isinstance(token, str):
            raise HttpError(400, "bad_request", "access_token must be a string")
        claims = self._parse_token(token, "access", req)
        with self.lock:
            self._revoke(claims["jti"], "logout")
        return {"ok": True}

    def handle_me(self, req):
        if req.method != "GET":
            raise HttpError(405, "method_not_allowed", "GET required")
        auth = req.headers.get("authorization", "")
        parts = auth.split(None, 1)
        if len(parts) != 2 or parts[0].lower() != "bearer":
            raise HttpError(401, "invalid_token", "missing Bearer token")
        claims = self._parse_token(parts[1].strip(), "access", req)
        return {
            "sub": claims["sub"],
            "iss": claims["iss"],
            "iat": claims["iat"],
            "exp": claims["exp"],
            "jti": claims["jti"],
            "typ": claims["typ"],
        }

    def handle_health(self, req):
        if req.method != "GET":
            raise HttpError(405, "method_not_allowed", "GET required")
        return {"status": "ok"}


def main():
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as fh:
            cfg = json.load(fh)
    except Exception as exc:
        sys.stderr.write("onyx: cannot read %s: %s\n" % (CONFIG_PATH, exc))
        sys.exit(1)
    svc = TokenService(cfg)
    handlers = {
        "/login": svc.handle_login,
        "/refresh": svc.handle_refresh,
        "/logout": svc.handle_logout,
        "/me": svc.handle_me,
        "/health": svc.handle_health,
    }
    host = str(cfg["host"])
    port = int(cfg["port"])
    sys.stderr.write("onyx: serving on %s:%d\n" % (host, port))
    serve(host, port, handlers)


if __name__ == "__main__":
    main()
PY
chmod +x /app/token_service.py

# ---- smoke test against the shipped (visible) config: start the service,
# login, /me with the access token, rotation, logout, restart persistence.
python3 - <<'PY'
import json
import os
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request

cfg = json.load(open("/app/config.json", encoding="utf-8"))
base = "http://127.0.0.1:%d" % cfg["port"]


def req(method, path, body=None, headers=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(base + path, data=data, method=method,
                               headers=headers or {})
    try:
        with urllib.request.urlopen(r, timeout=5) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        try:
            return exc.code, json.loads(exc.read().decode())
        except Exception:
            return exc.code, None


proc = subprocess.Popen([sys.executable, "/app/token_service.py"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    ok = False
    for _ in range(40):
        if proc.poll() is not None:
            break
        try:
            with urllib.request.urlopen(base + "/health", timeout=1) as resp:
                if resp.status == 200:
                    ok = True
                    break
        except Exception:
            time.sleep(0.1)
    assert ok, "service did not become healthy"
    st, body = req("POST", "/login",
                   {"user": "alice", "password": cfg["users"]["alice"]["password"]})
    assert st == 200, (st, body)
    access = body["access_token"]
    refresh = body["refresh_token"]
    st, body = req("GET", "/me", headers={"Authorization": "Bearer " + access})
    assert st == 200 and body["sub"] == "alice" and body["typ"] == "access", (st, body)
    st, body = req("POST", "/refresh", {"refresh_token": refresh})
    assert st == 200, (st, body)
    new_access = body["access_token"]
    st, body = req("POST", "/refresh", {"refresh_token": refresh})
    assert st == 401 and body["error"]["code"] == "token_revoked", (st, body)
    st, body = req("POST", "/logout", {"access_token": new_access})
    assert st == 200, (st, body)
    print("onyx oracle smoke test passed (port %d)" % cfg["port"])
finally:
    try:
        proc.terminate()
        proc.wait(timeout=5)
    except Exception:
        proc.kill()
PY

echo "sedge-hearth oracle complete -> /app/token_service.py"