#!/usr/bin/env python3
"""Mist Buoy tide-gauge archive service.

Usage: python3 server.py <data.json> <port>

Serves the REST API described by its own /contract.json endpoint. All
behaviour is derived from the data file, which also carries the contract
version, the archive key and the active campaign constants.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs


class Archive:
    def __init__(self, data):
        self.data = data
        self.jobs = {}          # job_id -> {"status", "result", "polls"}
        self.job_seq = 0

    # --- contract ----------------------------------------------------
    def contract(self):
        d = self.data
        return {
            "service": "Mist Buoy tide-gauge archive",
            "contract_version": d["contract_version"],
            "auth": {
                "header": "X-Archive-Key",
                "value": d["archive_key"],
                "failure_status": 403,
                "note": "Every /api/v2/ request must carry this header; "
                        "requests without it are rejected with 403 "
                        '{"error": {"code": "unauthorized"}}.',
            },
            "routes": [
                {
                    "method": "GET",
                    "path": "/api/v2/stations",
                    "query": {
                        "cursor": "opaque continuation token taken from the "
                                  "previous response's next_cursor; omit on "
                                  "the first call",
                        "limit": "page size, default 4, capped at 8",
                    },
                    "success": {
                        "status": 200,
                        "body": {
                            "stations": [
                                {"id": "str", "name": "str",
                                 "region": "str", "status": "str"}
                            ],
                            "next_cursor": "string token when more pages "
                                           "remain, else null",
                        },
                    },
                    "notes": "Stations are returned in fixed archive order; "
                             "iterate pages via next_cursor until it is null.",
                },
                {
                    "method": "POST",
                    "path": "/api/v2/reports",
                    "request_body": {
                        "station_ids": ["array of station id strings, "
                                        "mandatory, non-empty"],
                        "metric": "string, must be the campaign metric",
                        "window": {"from": "ISO timestamp, inclusive",
                                   "to": "ISO timestamp, exclusive"},
                    },
                    "success": {
                        "status": 202,
                        "body": {"job_id": "str"},
                    },
                    "errors": {
                        "malformed body / unknown station id / wrong metric "
                        "or missing window": '400 {"error": {"code": '
                        '"bad_request", "message": ...}}',
                    },
                    "notes": "Report jobs are asynchronous; poll the job "
                             "resource until status is done.",
                },
                {
                    "method": "GET",
                    "path": "/api/v2/reports/{job_id}",
                    "success": {
                        "status": 200,
                        "body": {
                            "job_id": "str",
                            "status": "queued | running | done",
                            "result": "null until done, then "
                                      "{stations, readings, min, mean, max}",
                        },
                    },
                    "errors": {
                        "unknown job id": '404 {"error": {"code": '
                        '"not_found", "message": ...}}',
                    },
                },
                {
                    "method": "GET",
                    "path": "/api/v2/stations/{id}",
                    "success": {"status": 200,
                                "body": "single station object or 404"},
                },
            ],
            "retired": {
                "routes": ["/api/v1/..."],
                "status": 410,
                "note": "The unversioned /api/v1/ paths are retired and "
                        "return 410 Gone. Do not use them.",
            },
            "campaign": d["campaign"],
        }

    # --- helpers -----------------------------------------------------
    @staticmethod
    def _err(code, message, status):
        return status, {"error": {"code": code, "message": message}}

    def _check_auth(self, headers):
        want = self.data["archive_key"]
        got = headers.get("X-Archive-Key")
        if got != want:
            return self._err(
                "unauthorized",
                "missing or invalid X-Archive-Key header", 403)
        return None

    def stations_page(self, qs):
        try:
            limit = int(qs.get("limit", ["4"])[0])
        except ValueError:
            return self._err("bad_request", "limit must be an integer", 400)
        limit = max(1, min(limit, 8))
        offset = 0
        cur = qs.get("cursor", [None])[0]
        if cur is not None:
            if not cur.startswith("c") or not cur[1:].isdigit():
                return self._err("bad_request", "unknown cursor", 400)
            offset = int(cur[1:])
        stations = self.data["stations"]
        page = stations[offset:offset + limit]
        nxt = "c%d" % (offset + limit) if offset + limit < len(stations) else None
        return 200, {"stations": page, "next_cursor": nxt}

    def station_detail(self, sid):
        for s in self.data["stations"]:
            if s["id"] == sid:
                return 200, s
        return self._err("not_found", "no such station", 404)

    def create_report(self, body):
        if not isinstance(body, dict):
            return self._err("bad_request", "body must be a JSON object", 400)
        ids = body.get("station_ids")
        metric = body.get("metric")
        window = body.get("window")
        if not isinstance(ids, list) or not ids or \
                not all(isinstance(x, str) for x in ids):
            return self._err("bad_request", "station_ids must be a "
                             "non-empty array of strings", 400)
        known = {s["id"] for s in self.data["stations"]}
        if any(x not in known for x in ids):
            return self._err("bad_request", "unknown station id", 400)
        if metric != self.data["campaign"]["metric"]:
            return self._err("bad_request", "metric must be the campaign "
                             "metric %r" % self.data["campaign"]["metric"], 400)
        if not isinstance(window, dict) or \
                not isinstance(window.get("from"), str) or \
                not isinstance(window.get("to"), str):
            return self._err("bad_request", "window must be an object with "
                             "string from/to", 400)
        self.job_seq += 1
        jid = "job-%d" % self.job_seq
        self.jobs[jid] = {"polls": 0, "spec": (ids, metric, dict(window))}
        return 202, {"job_id": jid}

    def report_result(self, spec):
        ids, metric, window = spec
        lo, hi = window["from"], window["to"]
        values = []
        readings = 0
        for sid in ids:
            for r in self.data["readings"].get(sid, []):
                if lo <= r["ts"] < hi:
                    readings += 1
                    values.append(float(r[metric]))
        result = {"stations": len(ids), "readings": readings,
                  "min": None, "mean": None, "max": None}
        if values:
            result["min"] = round(min(values), 4)
            result["mean"] = round(sum(values) / len(values), 4)
            result["max"] = round(max(values), 4)
        return result

    def job_status(self, jid):
        job = self.jobs.get(jid)
        if job is None:
            return self._err("not_found", "no such report job", 404)
        job["polls"] += 1
        if job["polls"] >= 3:
            job["status"] = "done"
            job["result"] = self.report_result(job["spec"])
        elif job["polls"] == 1:
            job["status"] = "queued"
        else:
            job["status"] = "running"
        return 200, {"job_id": jid, "status": job["status"],
                     "result": job.get("result")}


class Handler(BaseHTTPRequestHandler):
    archive = None  # set in main()

    def log_message(self, fmt, *args):  # silence request logging
        pass

    def _send(self, status, obj):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        seg = [s for s in u.path.split("/") if s]
        if u.path == "/contract.json":
            return self._send(200, self.archive.contract())
        if u.path.startswith("/api/v1"):
            return self._send(410, {"error": {"code": "gone",
                                  "message": "/api/v1/ is retired; use "
                                             "/api/v2/ per the contract"}})
        if seg[:2] == ["api", "v2"] and len(seg) >= 3 and seg[2] == "stations":
            denied = self.archive._check_auth(self.headers)
            if denied:
                return self._send(*denied)
            qs = parse_qs(u.query)
            if len(seg) == 3:
                return self._send(*self.archive.stations_page(qs))
            if len(seg) == 4:
                return self._send(*self.archive.station_detail(seg[3]))
        if seg[:3] == ["api", "v2", "reports"] and len(seg) == 4:
            denied = self.archive._check_auth(self.headers)
            if denied:
                return self._send(*denied)
            return self._send(*self.archive.job_status(seg[3]))
        return self._send(404, {"error": {"code": "not_found",
                              "message": "no such route; see /contract.json"}})

    def do_POST(self):
        u = urlparse(self.path)
        seg = [s for s in u.path.split("/") if s]
        if seg[:3] == ["api", "v2", "reports"] and len(seg) == 3:
            denied = self.archive._check_auth(self.headers)
            if denied:
                return self._send(*denied)
            try:
                length = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(length).decode() or "null")
            except Exception:
                return self._send(400, {"error": {"code": "bad_request",
                                      "message": "body must be valid JSON"}})
            return self._send(*self.archive.create_report(body))
        if u.path.startswith("/api/v1"):
            return self._send(410, {"error": {"code": "gone",
                                  "message": "/api/v1/ is retired"}})
        return self._send(404, {"error": {"code": "not_found",
                              "message": "no such route; see /contract.json"}})


def main():
    data_path, port = sys.argv[1], int(sys.argv[2])
    with open(data_path) as fh:
        data = json.load(fh)
    Handler.archive = Archive(data)
    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    srv.serve_forever()


if __name__ == "__main__":
    main()
