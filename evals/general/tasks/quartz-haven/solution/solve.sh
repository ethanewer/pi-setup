#!/bin/bash
# Oracle for quartz-haven: writes the deliverable service /app/api.py, then
# runs it against the visible fixture to produce /app/summary.json.
set -eu

cat > /app/api.py <<'PY'
"""Quartz Haven bulk portfolio ingestion service (stdlib-only WSGI)."""
import json
import re
import sys
from wsgiref.simple_server import make_server

STORE = {}  # asset_id -> record


class ApiError(Exception):
    def __init__(self, code, status):
        self.code = code
        self.status = status


def _num_ok(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and v >= 0


def validate_batch(assets):
    if not isinstance(assets, list) or not assets:
        raise ApiError("bad_request", "400 Bad Request")
    seen = set()
    for a in assets:
        if not isinstance(a, dict):
            raise ApiError("bad_request", "400 Bad Request")
        aid = a.get("asset_id")
        ticker = a.get("ticker")
        qty = a.get("quantity")
        price = a.get("price")
        if not isinstance(aid, str) or not aid:
            raise ApiError("bad_request", "400 Bad Request")
        if not isinstance(ticker, str) or not ticker:
            raise ApiError("bad_request", "400 Bad Request")
        if not _num_ok(qty) or not _num_ok(price):
            raise ApiError("bad_request", "400 Bad Request")
        if aid in seen or aid in STORE:
            raise ApiError("bad_request", "400 Bad Request")
        seen.add(aid)
    return seen


def handle_bulk(payload):
    if not isinstance(payload, dict):
        raise ApiError("bad_request", "400 Bad Request")
    ids = validate_batch(payload.get("assets"))
    assets = payload["assets"]
    for a in assets:
        STORE[a["asset_id"]] = {
            "asset_id": a["asset_id"],
            "ticker": a["ticker"].upper(),
            "quantity": a["quantity"],
            "price": a["price"],
        }
    return {"accepted": len(assets), "total": len(STORE)}


def handle_summary():
    by_ticker = {}
    total = 0.0
    for r in STORE.values():
        t = r["ticker"]
        v = r["quantity"] * r["price"]
        e = by_ticker.setdefault(t, {"count": 0, "value": 0.0})
        e["count"] += 1
        e["value"] += v
        total += v
    return {
        "count": len(STORE),
        "total_value": total,
        "by_ticker": by_ticker,
    }


def route(method, path, payload):
    if method == "GET" and path == "/api/v1/health":
        return {"status": "ok"}
    if method == "POST" and path == "/api/v1/assets/bulk":
        return handle_bulk(payload)
    if method == "GET" and path == "/api/v1/portfolio/summary":
        return handle_summary()
    m = re.match(r"^/api/v1/assets/(.+)$", path)
    if method == "GET" and m:
        rec = STORE.get(m.group(1))
        if rec is None:
            raise ApiError("not_found", "404 Not Found")
        return rec
    raise ApiError("bad_request", "400 Bad Request")


def application(environ, start_response):
    try:
        length = int(environ.get("CONTENT_LENGTH") or 0)
    except (TypeError, ValueError):
        length = 0
    raw = environ["wsgi.input"].read(length) if length else b""
    try:
        payload = json.loads(raw.decode("utf-8")) if raw else None
    except (ValueError, UnicodeDecodeError):
        payload = None
    try:
        body = route(environ["REQUEST_METHOD"],
                     environ.get("PATH_INFO", "/"), payload)
        status = "200 OK"
        if environ["REQUEST_METHOD"] == "POST" and \
                environ.get("PATH_INFO") == "/api/v1/assets/bulk":
            status = "201 Created"
    except ApiError as e:
        body = {"error": {"code": e.code}}
        status = e.status
    data = json.dumps(body).encode("utf-8")
    start_response(status, [("Content-Type", "application/json"),
                            ("Content-Length", str(len(data)))])
    return [data]


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    with make_server("127.0.0.1", port, application) as srv:
        srv.serve_forever()


if __name__ == "__main__":
    main()
PY

chmod +x /app/api.py

# Produce the visible-case deliverable by driving the just-written service.
python3 - <<'PY'
import importlib.util
import json

spec = importlib.util.spec_from_file_location("qh_api", "/app/api.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

environ_base = {
    "SERVER_NAME": "127.0.0.1", "SERVER_PORT": "80", "SERVER_PROTOCOL": "HTTP/1.1",
    "wsgi.version": (1, 0), "wsgi.url_scheme": "http", "wsgi.errors": None,
    "wsgi.multithread": False, "wsgi.multiprocess": False, "wsgi.run_once": False,
}


def call(method, path, body=None):
    import io
    raw = json.dumps(body).encode() if body is not None else b""
    env = dict(environ_base)
    env.update({"REQUEST_METHOD": method, "PATH_INFO": path,
                "CONTENT_LENGTH": str(len(raw)),
                "CONTENT_TYPE": "application/json",
                "wsgi.input": io.BytesIO(raw), "wsgi.errors": io.StringIO()})
    out = {}
    chunks = mod.application(env, lambda s, h, e=None: out.update(s=s))
    data = b"".join(chunks)
    return int(out["s"].split()[0]), json.loads(data)


with open("/app/visible_portfolio.json") as fh:
    payload = json.load(fh)
status, resp = call("POST", "/api/v1/assets/bulk", payload)
assert status == 201 and resp["accepted"] == len(payload["assets"]), resp
status, summary = call("GET", "/api/v1/portfolio/summary")
assert status == 200, summary
with open("/app/summary.json", "w") as fh:
    json.dump(summary, fh, indent=2, sort_keys=True)
print("oracle: ingested", resp["accepted"], "assets; summary written")
PY

echo "solve.sh done"
