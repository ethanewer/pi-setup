#!/usr/bin/env python3
"""
RelayGrid console origin server (reference implementation).

Serves a small JSON-over-HTTP authentication service with a
challenge/response login, an authenticated task listing, and session
termination via logout.

Usage:
    python3 relayd.py --config scenario.json --port PORT --audit audit.jsonl

The scenario config declares:
    user        -- the only accepted username
    passphrase  -- the shared secret used to derive the login proof
    iterations  -- how many times the proof digest is iterated (>= 1)
    tasks       -- the task objects served to authenticated sessions

Every state change is appended to the audit file as one JSON object per
line: event in {challenge, login_ok, login_failed, tasks_ok, logout_ok,
auth_rejected}.
"""

import argparse
import hashlib
import json
import secrets
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def sha256_hex(s):
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


class RelayState:
    def __init__(self, cfg):
        self.user = cfg["user"]
        self.passphrase = cfg["passphrase"]
        self.iterations = int(cfg.get("iterations", 1))
        self.tasks = cfg.get("tasks", [])
        self.challenges = set()
        self.sessions = set()
        self.lock = threading.Lock()

    def expected_proof(self, challenge):
        proof = sha256_hex(challenge + ":" + self.passphrase)
        for _ in range(self.iterations - 1):
            proof = sha256_hex(proof)
        return proof


class Audit:
    def __init__(self, path):
        self.fh = open(path, "a", encoding="utf-8", buffering=1)
        self.lock = threading.Lock()

    def emit(self, event, **detail):
        rec = {"event": event}
        rec.update(detail)
        with self.lock:
            self.fh.write(json.dumps(rec) + "\n")


class Handler(BaseHTTPRequestHandler):
    state = None  # type: RelayState
    audit = None  # type: Audit

    def log_message(self, *args):
        pass

    def _reply(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _bearer(self):
        header = self.headers.get("Authorization", "")
        if header.startswith("Bearer "):
            return header[len("Bearer "):].strip()
        return None

    def do_GET(self):
        if self.path == "/api/challenge":
            challenge = secrets.token_hex(8)
            with self.state.lock:
                self.state.challenges.add(challenge)
            self.audit.emit("challenge", challenge=challenge)
            self._reply(200, {
                "challenge": challenge,
                "iterations": self.state.iterations,
            })
            return
        if self.path == "/api/tasks":
            token = self._bearer()
            if token and token in self.state.sessions:
                self.audit.emit("tasks_ok", count=len(self.state.tasks))
                self._reply(200, {"tasks": self.state.tasks})
            else:
                self.audit.emit("auth_rejected", route="/api/tasks")
                self._reply(401, {"error": "unauthorized"})
            return
        self._reply(404, {"error": "not_found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(length) if length else b""
        if self.path == "/api/login":
            if self.headers.get("X-Client", "") != "grid-cli":
                self.audit.emit("login_failed", reason="client_header")
                self._reply(400, {"error": "missing_client_header"})
                return
            try:
                body = json.loads(raw.decode("utf-8"))
            except Exception:
                body = {}
            user = body.get("user")
            challenge = body.get("challenge")
            proof = body.get("proof")
            with self.state.lock:
                issued = challenge in self.state.challenges
            if (
                user != self.state.user
                or not issued
                or not isinstance(proof, str)
                or proof != self.state.expected_proof(challenge)
            ):
                self.audit.emit("login_failed", user=user)
                self._reply(403, {"error": "auth_failed"})
                return
            token = secrets.token_hex(12)
            with self.state.lock:
                self.state.sessions.add(token)
            self.audit.emit("login_ok", user=user, session=token,
                            challenge=challenge)
            self._reply(200, {"session": token, "user": user})
            return
        if self.path == "/api/logout":
            token = self._bearer()
            if token and token in self.state.sessions:
                with self.state.lock:
                    self.state.sessions.discard(token)
                self.audit.emit("logout_ok", session=token)
                self._reply(200, {"logged_out": True})
            else:
                self.audit.emit("auth_rejected", route="/api/logout")
                self._reply(401, {"error": "unauthorized"})
            return
        self._reply(404, {"error": "not_found"})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--audit", required=True)
    args = ap.parse_args()

    with open(args.config, "r", encoding="utf-8") as fh:
        cfg = json.load(fh)

    Handler.state = RelayState(cfg)
    Handler.audit = Audit(args.audit)

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
