#!/usr/bin/env python3
"""Harborline planner service (read-only environment fixture).

Serves provisioning requests over a paginated JSON API, accepts exactly one
plan record per request, and commits the plans file. Do NOT modify this file.
"""
import argparse
import hashlib
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

VCPU_PER = {"basic": 1, "standard": 2, "performance": 4}
MEM_GIB_PER = {"basic": 2, "standard": 4, "performance": 8}
DEFAULT_LIMIT = 25
MAX_LIMIT = 40


def expected_shape(req):
    tier = req["tier"]
    reps = int(req["replicas"])
    storage = int(req["storage_gb"])
    gpu = bool(req.get("gpu", False))
    vcpus = VCPU_PER[tier] * reps + (8 if gpu else 0)
    memory_gib = MEM_GIB_PER[tier] * reps
    disk_gib = ((storage + 15) // 16) * 16
    if disk_gib < 16:
        disk_gib = 16
    return {"vcpus": vcpus, "memory_gib": memory_gib, "disk_gib": disk_gib}


class Session:
    def __init__(self, case_path, out_path):
        with open(case_path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        self.requests = data["requests"]
        self.by_id = {r["id"]: r for r in self.requests}
        self.session = data["session"]
        self.out_path = out_path
        self.planned = {}
        self.status = "open"
        self.lock = threading.Lock()

    def submit(self, rec):
        with self.lock:
            if self.status != "open":
                return 409, {"error": "session-failed", "status": self.status}
            if not isinstance(rec, dict):
                return 400, {"error": "schema",
                             "detail": "record must be a JSON object with keys id, batch, shape"}
            if set(rec.keys()) != {"id", "batch", "shape"}:
                return 400, {"error": "schema",
                             "detail": "record keys must be exactly id, batch, shape"}
            rid = rec["id"]
            if not isinstance(rid, str) or rid not in self.by_id:
                return 400, {"error": "unknown-id", "id": rid}
            if rid in self.planned:
                self.status = "duplicate-plan"
                return 409, {"error": "duplicate-plan",
                             "detail": "each request id may receive exactly one record; "
                                       "session permanently failed",
                             "status": self.status}
            req = self.by_id[rid]
            if rec["batch"] != req["batch"]:
                return 400, {"error": "batch-mismatch",
                             "detail": "batch must equal the request's batch id"}
            shape = rec["shape"]
            if not isinstance(shape, dict) or set(shape.keys()) != {
                    "vcpus", "memory_gib", "disk_gib"}:
                return 400, {"error": "shape-schema",
                             "detail": "shape keys must be exactly "
                                       "vcpus, memory_gib, disk_gib"}
            want = expected_shape(req)
            for k in ("vcpus", "memory_gib", "disk_gib"):
                if type(shape[k]) is not int:
                    return 400, {"error": "shape-mismatch", "field": k,
                                 "detail": "must be an integer"}
                if shape[k] != want[k]:
                    return 400, {"error": "shape-mismatch", "field": k,
                                 "detail": "does not match the documented derivation"}
            self.planned[rid] = {"id": rid, "batch": rec["batch"], "shape": dict(want)}
            return 200, {"ok": True, "id": rid, "submitted": len(self.planned),
                         "total": len(self.requests)}

    def commit(self):
        with self.lock:
            missing = [r["id"] for r in self.requests if r["id"] not in self.planned]
            result = {"session": self.session, "submitted": len(self.planned),
                      "total": len(self.requests), "missing": len(missing)}
            if missing or self.status != "open":
                result["committed"] = False
                result["status"] = self.status
                result["sha256"] = ""
                return 200, result
            lines = []
            for r in self.requests:
                rec = self.planned[r["id"]]
                lines.append(json.dumps(
                    {"id": rec["id"], "batch": rec["batch"], "shape": rec["shape"]},
                    separators=(",", ":")))
            payload = ("\n".join(lines) + "\n").encode("utf-8")
            with open(self.out_path, "wb") as fh:
                fh.write(payload)
            self.status = "committed"
            result["committed"] = True
            result["status"] = "committed"
            result["records"] = len(lines)
            result["sha256"] = hashlib.sha256(payload).hexdigest()
            return 200, result


SESSION = None


class Handler(BaseHTTPRequestHandler):
    server_version = "PlannerService/1.0"

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
        u = urlparse(self.path)
        if u.path == "/api/session":
            self._json(200, {"session": SESSION.session,
                             "total": len(SESSION.requests),
                             "submitted": len(SESSION.planned),
                             "status": SESSION.status})
        elif u.path == "/api/requests":
            q = parse_qs(u.query)
            try:
                offset = int(q.get("offset", ["0"])[0])
                limit = int(q.get("limit", [str(DEFAULT_LIMIT)])[0])
            except (TypeError, ValueError):
                self._json(400, {"error": "bad-pagination"})
                return
            if offset < 0:
                offset = 0
            if limit < 1:
                limit = 1
            if limit > MAX_LIMIT:
                limit = MAX_LIMIT
            page = SESSION.requests[offset:offset + limit]
            self._json(200, {"total": len(SESSION.requests), "offset": offset,
                             "limit": limit, "requests": page})
        else:
            self._json(404, {"error": "not-found"})

    def do_POST(self):
        u = urlparse(self.path)
        n = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(n)
        if u.path == "/api/plan":
            try:
                rec = json.loads(raw.decode("utf-8"))
            except Exception:
                self._json(400, {"error": "invalid-json"})
                return
            code, obj = SESSION.submit(rec)
            self._json(code, obj)
        elif u.path == "/api/commit":
            code, obj = SESSION.commit()
            self._json(code, obj)
        else:
            self._json(404, {"error": "not-found"})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--serve", action="store_true")
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--case", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    global SESSION
    SESSION = Session(args.case, args.out)
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    srv.serve_forever()


if __name__ == "__main__":
    main()
