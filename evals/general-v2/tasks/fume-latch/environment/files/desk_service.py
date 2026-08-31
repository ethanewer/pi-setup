#!/usr/bin/env python3
"""Fume Latch repair-desk service.

A deterministic HTTP JSON service that holds a defective plate file in memory
and accepts per-line fix requests. Every ACCEPTED fix request consumes one
unit of the session's fix budget; when the budget is exhausted, further fix
requests are refused with 409 and the session status becomes
"budget-exceeded" permanently. Committing does not consume budget: it writes
the in-memory plate back to the workfile and reports whether every line now
matches the expected content.

Do not modify this file; the verifier starts fresh copies of it.

API:
  GET  /api/session    -> {"session", "lines", "budget", "fixes_used", "status"}
  GET  /api/integrity  -> {"integrity": [bool per line], "all_fixed": bool}
  POST /api/fix        {"line": <1-based int>, "content": "<exact new line>"}
  POST /api/commit     -> receipt (does NOT consume budget)
"""

import argparse
import hashlib
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CASE = {}
STATE = {
    "session": "",
    "lines": [],
    "budget": 0,
    "fixes_used": 0,
    "status": "open",
}


def load_case(path):
    global CASE
    with open(path, "r", encoding="utf-8") as f:
        CASE = json.load(f)
    with open(CASE["workfile"], "r", encoding="utf-8") as f:
        raw = f.read()
    lines = raw.split("\n")
    if lines and lines[-1] == "":
        lines.pop()  # drop the artifact of a trailing newline
    STATE["lines"] = lines
    STATE["budget"] = int(CASE["budget"])
    STATE["session"] = str(CASE.get("session", "case"))
    STATE["fixes_used"] = 0
    STATE["status"] = "open"


def expected_bytes():
    return ("\n".join(CASE["expected"]) + "\n").encode("utf-8")


def plate_bytes():
    return ("\n".join(STATE["lines"]) + "\n").encode("utf-8")


def sha256_hex(b):
    return hashlib.sha256(b).hexdigest()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _not_found(self):
        self._send(404, {"error": {"code": "not_found",
                                   "message": "unknown route"}})

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/api/session":
            self._send(200, {
                "session": STATE["session"],
                "lines": len(STATE["lines"]),
                "budget": STATE["budget"],
                "fixes_used": STATE["fixes_used"],
                "status": STATE["status"],
            })
        elif path == "/api/integrity":
            exp = CASE["expected"]
            integ = [STATE["lines"][i] == exp[i]
                     for i in range(min(len(STATE["lines"]), len(exp)))]
            self._send(200, {"integrity": integ,
                             "all_fixed": STATE["lines"] == exp})
        else:
            self._not_found()

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        if path not in ("/api/fix", "/api/commit"):
            self._not_found()
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length).decode("utf-8")) \
                if length else None
        except Exception:
            self._send(400, {"error": {"code": "bad_request",
                                       "message": "body is not valid JSON"}})
            return
        if path == "/api/commit":
            self._commit()
            return
        # /api/fix
        if not isinstance(body, dict):
            self._send(400, {"error": {"code": "bad_request",
                                       "message": "body must be an object"}})
            return
        line = body.get("line")
        content = body.get("content")
        if isinstance(line, bool) or not isinstance(line, int) \
                or line < 1 or line > len(STATE["lines"]):
            self._send(400, {"error": {"code": "bad_request",
                                       "message": "line must be a 1-based "
                                                  "integer within range"}})
            return
        if not isinstance(content, str):
            self._send(400, {"error": {"code": "bad_request",
                                       "message": "content must be a string"}})
            return
        if STATE["status"] == "budget-exceeded" \
                or STATE["fixes_used"] >= STATE["budget"]:
            STATE["status"] = "budget-exceeded"
            self._send(409, {"error": {"code": "budget_exhausted",
                                       "message": "fix budget exhausted; "
                                                  "session failed"}})
            return
        STATE["lines"][line - 1] = content
        STATE["fixes_used"] += 1
        self._send(200, {"ok": True, "line": line,
                         "fixes_used": STATE["fixes_used"],
                         "budget": STATE["budget"]})

    def _commit(self):
        exp = CASE["expected"]
        mismatched = [i + 1 for i in range(max(len(STATE["lines"]), len(exp)))
                      if (STATE["lines"][i] if i < len(STATE["lines"]) else None)
                      != (exp[i] if i < len(exp) else None)]
        all_fixed = STATE["lines"] == exp
        if mismatched:
            with open(CASE["workfile"], "w", encoding="utf-8") as f:
                f.write("\n".join(STATE["lines"]) + "\n")
        else:
            with open(CASE["workfile"], "w", encoding="utf-8") as f:
                f.write("\n".join(exp) + "\n")
        self._send(200, {
            "session": STATE["session"],
            "all_fixed": all_fixed,
            "fixes_used": STATE["fixes_used"],
            "budget": STATE["budget"],
            "status": STATE["status"],
            "sha256": sha256_hex(plate_bytes()),
            "mismatched_lines": mismatched,
        })

    def log_message(self, fmt, *args):  # quiet
        pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--serve", action="store_true")
    ap.add_argument("--port", type=int, default=8471)
    ap.add_argument("--case", required=True, help="path to the case JSON")
    args = ap.parse_args()
    if not args.serve:
        ap.error("--serve is required")
    load_case(args.case)
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    srv.serve_forever()


if __name__ == "__main__":
    main()
