#!/usr/bin/env python3
"""Radar Relay — a small deterministic HTTP service.

Usage: python3 /app/service.py <profile.json> <port>

The service's contract is served at GET /api/doc.json (no auth). Everything
else lives under /api/v2/* and requires the auth header named in the doc.
Standard library only; deterministic; binds 127.0.0.1.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs

AUTH_HEADER = "X-Radar-Key"
METRICS = ("mean", "max", "min", "count")

with open(sys.argv[1], "r", encoding="utf-8") as _fh:
    PROFILE = json.load(_fh)

KEY = PROFILE["key"]
STATIONS = {s["id"]: s for s in PROFILE["stations"]}
_query_counter = {"n": 0}
_queries = {}


def compute_metric(station, metric):
    values = [r["value"] for r in STATIONS[station]["readings"]]
    if metric == "mean":
        return sum(values) / len(values)
    if metric == "max":
        return max(values)
    if metric == "min":
        return min(values)
    if metric == "count":
        return len(values)
    raise ValueError(metric)


def build_doc():
    return {
        "service": "Radar Relay",
        "version": "2.1",
        "auth": {
            "mechanism": "header",
            "header": AUTH_HEADER,
            "value": KEY,
            "applies_to": ("every /api/v2/* request must carry this header "
                           "with exactly this value; requests without it "
                           "receive 401"),
        },
        "endpoints": {
            "doc": {
                "method": "GET",
                "path": "/api/doc.json",
                "auth_required": False,
                "description": "This contract document.",
            },
            "stations": {
                "method": "GET",
                "path": "/api/v2/stations",
                "auth_required": True,
                "description": "List every radar station known to the relay.",
                "response_shape": {
                    "stations": [
                        {"id": "string", "name": "string",
                         "lat": "number", "lon": "number"}
                    ]
                },
            },
            "readings": {
                "method": "GET",
                "path": "/api/v2/readings",
                "auth_required": True,
                "query": {
                    "station": "required; id of the station to read",
                    "limit": ("required; non-negative integer; at most this "
                              "many readings are returned"),
                },
                "notes": ("readings are returned in stored order; to receive "
                          "ALL of a station's readings, pass a limit at least "
                          "as large as its reading count"),
                "response_shape": {
                    "station": "string",
                    "count": "integer",
                    "readings": [
                        {"taken_at": "string", "value": "number"}
                    ],
                },
                "errors": {
                    "400": "missing/invalid query params",
                    "401": "missing or wrong auth header",
                    "404": "unknown station id",
                },
            },
            "submit_query": {
                "method": "POST",
                "path": "/api/v2/queries",
                "auth_required": True,
                "content_type": "application/json",
                "body_shape": {
                    "station": "required; id of the station to aggregate",
                    "metric": "required; one of mean|max|min|count",
                },
                "success": ("202 with body {\"query_id\": \"<id>\", "
                            "\"status\": \"queued\"}"),
                "notes": ("the query aggregates over ALL of the station's "
                          "readings, regardless of any limit used when "
                          "fetching readings"),
                "errors": {
                    "400": "malformed body, unknown metric, or bad types",
                    "401": "missing or wrong auth header",
                    "404": "unknown station id",
                },
            },
            "poll_query": {
                "method": "GET",
                "path": "/api/v2/queries/{query_id}",
                "auth_required": True,
                "response_shape": {
                    "query_id": "string",
                    "status": "queued until the result is ready, then done",
                    "result": {
                        "station": "string",
                        "metric": "string",
                        "value": "number (count is an integer)",
                    },
                },
                "notes": "poll until status is \"done\".",
                "errors": {
                    "401": "missing or wrong auth header",
                    "404": "unknown query_id",
                },
            },
        },
        "metrics": list(METRICS),
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "RadarRelay/2.1"

    def log_message(self, *args):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _err(self, code, ecode, message):
        self._send(code, {"error": {"code": ecode, "message": message}})

    def _authed(self):
        return self.headers.get(AUTH_HEADER) == KEY

    def do_GET(self):
        parts = urlsplit(self.path)
        path = parts.path.rstrip("/") or parts.path
        if path == "/api/doc.json":
            self._send(200, build_doc())
            return
        if not self._authed():
            self._err(401, "unauthorized",
                      "missing or incorrect %s header" % AUTH_HEADER)
            return
        if path == "/api/v2/stations":
            listing = [{"id": s["id"], "name": s["name"],
                        "lat": s["lat"], "lon": s["lon"]}
                       for s in PROFILE["stations"]]
            self._send(200, {"stations": listing})
            return
        if path == "/api/v2/readings":
            qs = parse_qs(parts.query)
            station = (qs.get("station") or [None])[0]
            limit_raw = (qs.get("limit") or [None])[0]
            if station is None:
                self._err(400, "bad_request", "station query param required")
                return
            if station not in STATIONS:
                self._err(404, "not_found", "unknown station %r" % station)
                return
            try:
                limit = int(limit_raw)
            except (TypeError, ValueError):
                self._err(400, "bad_request",
                          "limit must be a non-negative integer")
                return
            if limit < 0:
                self._err(400, "bad_request",
                          "limit must be a non-negative integer")
                return
            readings = STATIONS[station]["readings"][:limit]
            self._send(200, {"station": station,
                             "count": len(readings),
                             "readings": readings})
            return
        if path.startswith("/api/v2/queries/"):
            qid = path[len("/api/v2/queries/"):]
            if qid not in _queries:
                self._err(404, "not_found", "unknown query_id %r" % qid)
                return
            self._send(200, _queries[qid])
            return
        self._err(404, "not_found", "no route for %s" % path)

    def do_POST(self):
        parts = urlsplit(self.path)
        path = parts.path.rstrip("/") or parts.path
        if path != "/api/v2/queries":
            self._err(404, "not_found", "no route for %s" % path)
            return
        if not self._authed():
            self._err(401, "unauthorized",
                      "missing or incorrect %s header" % AUTH_HEADER)
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length).decode("utf-8"))
            assert isinstance(body, dict)
        except Exception:
            self._err(400, "bad_request", "body must be a JSON object")
            return
        station = body.get("station")
        metric = body.get("metric")
        if not isinstance(station, str) or not isinstance(metric, str):
            self._err(400, "bad_request",
                      "station and metric must be strings")
            return
        if station not in STATIONS:
            self._err(404, "not_found", "unknown station %r" % station)
            return
        if metric not in METRICS:
            self._err(400, "bad_request",
                      "metric must be one of %s" % "|".join(METRICS))
            return
        _query_counter["n"] += 1
        qid = "q-%d" % _query_counter["n"]
        _queries[qid] = {
            "query_id": qid,
            "status": "done",
            "result": {"station": station, "metric": metric,
                       "value": compute_metric(station, metric)},
        }
        self._send(202, {"query_id": qid, "status": "queued"})


def main():
    port = int(sys.argv[2])
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
