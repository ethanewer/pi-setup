#!/usr/bin/env python3
"""Wren Quarry defect-service.

A deterministic, offline, stdlib-only HTTP service that tracks per-line
defect-repair requests against a fix budget.  All state is persisted to a
JSON state file so a restarted server resumes exactly where it left off.

Endpoints (bind 127.0.0.1, default port 8710):
  GET  /defects -> {"file", "budget", "fixes_used", "remaining", "locked",
                    "defects": [{"id", "line", "kind", "current", "expected"}]}
  GET  /status  -> {"file", "budget", "fixes_used", "remaining", "locked",
                    "applied": [{"seq", "line", "before", "after"}],
                    "final_sha256", "initial_sha256"}
  POST /fix     body {"line": <1-based int>, "content": "<full replacement line>"}
                -> consumes ONE fix attempt ALWAYS (successful or not);
                   applies the line replacement when the line number is valid.
                -> 409 {"ok": false, "reason": "budget-exhausted"} once the
                   budget is spent and the service is locked.

Usage:
  python3 defect_server.py [--port 8710] [--file /app/pipeline/rectify.py]
                           [--state /app/ops/state.json] [--budget 8]
"""

import argparse
import hashlib
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEFECTS = [
    {"id": "d1", "line": 14, "kind": "accumulator-clobber",
     "expected": "running_total: every value must be ADDED to the running "
                 "accumulator so out[i] = values[0] + ... + values[i]."},
    {"id": "d2", "line": 30, "kind": "off-by-one",
     "expected": "moving_average: the loop must cover ALL full windows, "
                 "yielding exactly len(values) - window + 1 means."},
    {"id": "d3", "line": 37, "kind": "swapped-bounds",
     "expected": "clip_values: clamping must be min(max(v, lo), hi) so every "
                 "value lands inside [lo, hi]."},
    {"id": "d4", "line": 47, "kind": "stride-shift",
     "expected": "chunked: chunk starts must advance by exactly n, producing "
                 "ceil(len/n) chunks with a short final chunk."},
    {"id": "d5", "line": 58, "kind": "sort-order",
     "expected": "top_k: must return the k LARGEST values in DESCENDING "
                 "order (k <= 0 yields [])."},
]

STATE_VERSION = 1


class ServiceState:
    def __init__(self, path, file_path, budget):
        self.path = path
        self.file_path = file_path
        self.budget = budget
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as fh:
                    raw = json.load(fh)
                if raw.get("version") == STATE_VERSION and raw.get("file") == file_path:
                    self.data = raw
                    return
            except Exception:
                pass
        with open(file_path, "rb") as fh:
            data = fh.read()
        self.data = {
            "version": STATE_VERSION,
            "file": file_path,
            "budget": budget,
            "initial_sha256": hashlib.sha256(data).hexdigest(),
            "final_sha256": hashlib.sha256(data).hexdigest(),
            "fixes_used": 0,
            "locked": False,
            "applied": [],
        }
        self.save()

    def save(self):
        tmp = self.path + ".tmp"
        os.makedirs(os.path.dirname(self.path) or ".", exist_ok=True)
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(self.data, fh, indent=2)
        os.replace(tmp, self.path)

    def defect_report(self):
        with open(self.file_path, "r", encoding="utf-8") as fh:
            lines = fh.read().split("\n")
        out = []
        for d in DEFECTS:
            cur = lines[d["line"] - 1] if d["line"] <= len(lines) else ""
            out.append({"id": d["id"], "line": d["line"], "kind": d["kind"],
                        "current": cur, "expected": d["expected"]})
        return out


class Handler(BaseHTTPRequestHandler):
    state = None  # set in main()

    def log_message(self, *args):  # keep stdout quiet
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        st = self.state.data
        used = st["fixes_used"]
        base = {"file": st["file"], "budget": st["budget"],
                "fixes_used": used, "remaining": max(0, st["budget"] - used),
                "locked": st["locked"]}
        if self.path == "/defects":
            base["defects"] = self.state.defect_report()
            self._send(200, base)
        elif self.path == "/status":
            base["applied"] = st["applied"]
            base["final_sha256"] = st["final_sha256"]
            base["initial_sha256"] = st["initial_sha256"]
            self._send(200, base)
        else:
            self._send(404, {"ok": False, "reason": "not-found"})

    def do_POST(self):
        st = self.state.data
        if self.path != "/fix":
            self._send(404, {"ok": False, "reason": "not-found"})
            return
        if st["locked"]:
            self._send(409, {"ok": False, "reason": "budget-exhausted",
                             "fixes_used": st["fixes_used"],
                             "budget": st["budget"]})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            line_no = payload["line"]
            content = payload["content"]
        except Exception:
            # a malformed request still burns a fix attempt
            st["fixes_used"] += 1
            self._finish(400, False, "malformed-request")
            return
        if not isinstance(line_no, int) or isinstance(line_no, bool) \
                or not isinstance(content, str):
            st["fixes_used"] += 1
            self._finish(400, False, "malformed-request")
            return
        with open(self.state.file_path, "r", encoding="utf-8") as fh:
            lines = fh.read().split("\n")
        if not (1 <= line_no <= len(lines)):
            st["fixes_used"] += 1
            self._finish(400, False, "line-out-of-range")
            return
        before = lines[line_no - 1]
        lines[line_no - 1] = content
        with open(self.state.file_path, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines))
        st["fixes_used"] += 1
        st["applied"].append({"seq": len(st["applied"]) + 1, "line": line_no,
                              "before": before, "after": content})
        with open(self.state.file_path, "rb") as fh:
            st["final_sha256"] = hashlib.sha256(fh.read()).hexdigest()
        self._finish(200, True, None)

    def _finish(self, code, applied, reason):
        st = self.state.data
        if st["fixes_used"] >= st["budget"]:
            st["locked"] = True
        self.state.save()
        body = {"ok": True, "applied": applied, "fixes_used": st["fixes_used"],
                "budget": st["budget"],
                "remaining": max(0, st["budget"] - st["fixes_used"]),
                "locked": st["locked"]}
        if reason:
            body["reason"] = reason
        self._send(code, body)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8710)
    ap.add_argument("--file", default="/app/pipeline/rectify.py")
    ap.add_argument("--state", default="/app/ops/state.json")
    ap.add_argument("--budget", type=int, default=8)
    args = ap.parse_args()
    if not os.path.isfile(args.file):
        print("target file missing: %s" % args.file, file=sys.stderr)
        return 2
    Handler.state = ServiceState(args.state, args.file, args.budget)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print("defect-service listening on 127.0.0.1:%d" % args.port)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
