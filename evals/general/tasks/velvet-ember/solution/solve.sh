#!/bin/bash
# Oracle for velvet-ember: writes the hardened /app/normalize.py and
# /app/gateway.py, then runs the CLI on the visible fixture to produce
# /app/canonical_map.json.
set -eu

cat > /app/normalize.py <<'PY'
"""Velvet Ember hardened header-name normalization."""
import json
import sys

TOKEN_EXTRA = set("!#$%&'*+-.^_`|~")


class HeaderError(ValueError):
    """Raised for any header name that must not be forwarded."""


def canonical_header(name):
    if not isinstance(name, str) or name == "":
        raise HeaderError("header name must be a non-empty string")
    for ch in name:
        if not (ch in TOKEN_EXTRA or (ord(ch) < 128 and ch.isalnum())):
            raise HeaderError("invalid character %r in header name" % ch)
    return "-".join(t[:1].upper() + t[1:].lower() for t in name.split("-"))


def main(argv):
    if len(argv) != 3:
        print("usage: python3 normalize.py <in.json> <out.json>",
              file=sys.stderr)
        return 2
    with open(argv[1], "r", encoding="utf-8") as fh:
        entries = json.load(fh)
    out = []
    for x in entries:
        try:
            c = canonical_header(x)
            out.append({"input": x, "ok": True, "canonical": c})
        except HeaderError:
            out.append({"input": x, "ok": False, "canonical": None})
    with open(argv[2], "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=1, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

cat > /app/gateway.py <<'PY'
"""Velvet Ember Relay — hardened header relay (stdlib WSGI)."""
import json
import sys
from wsgiref.simple_server import make_server

from normalize import canonical_header, HeaderError


def route(method, path, payload):
    if method == "GET" and path == "/relay/health":
        return 200, {"status": "ok"}
    if method == "POST" and path == "/relay/headers":
        if not isinstance(payload, dict):
            return 400, {"error": {"code": "bad_request"}}
        for v in payload.values():
            if not isinstance(v, str):
                return 400, {"error": {"code": "bad_request"}}
        out = {}
        for raw in payload:
            try:
                canon = canonical_header(raw)
            except HeaderError:
                return 400, {"error": {"code": "invalid_header"}}
            if canon in out:
                return 400, {"error": {"code": "duplicate_header"}}
            out[canon] = payload[raw]
        return 200, {"headers": out}
    return 404, {"error": {"code": "not_found"}}


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
    status, body = route(environ["REQUEST_METHOD"],
                         environ.get("PATH_INFO", "/"), payload)
    data = json.dumps(body).encode("utf-8")
    start_response("%d %s" % (status, "OK" if status < 400 else "Error"),
                   [("Content-Type", "application/json"),
                    ("Content-Length", str(len(data)))])
    return [data]


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    with make_server("127.0.0.1", port, application) as srv:
        srv.serve_forever()


if __name__ == "__main__":
    main()
PY

chmod +x /app/normalize.py /app/gateway.py

# Visible deliverable: run the CLI on the shipped fixture.
python3 /app/normalize.py /app/visible_names.json /app/canonical_map.json

echo "solve.sh done"
