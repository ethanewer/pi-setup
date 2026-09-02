#!/bin/bash
# Real oracle for onyx-rudder: write the hardened normalizer module + gateway,
# then run the batch scan CLI on the visible fixture to produce
# /app/scan_report.json. Never reads /tests.
set -eu

MODULE="/app/hdrnorm.py"
GATEWAY="/app/gateway.py"
REPORT="/app/scan_report.json"
SCAN_IN="/app/header_scan.json"

# ---- 1. The hardened normalizer (module + scan CLI) ----
cat > "$MODULE" <<'PY'
"""Onyx Rudder hardened header-name normalizer (CWE-113 mitigation)."""
import json
import sys


def canonical_header(name):
    """Canonical title-form of an HTTP header name.

    Raises ValueError when `name` is not a non-empty `str` or contains any
    control character (ord(c) < 0x20 or ord(c) == 0x7f).  Everything else is
    accepted: split on '-', title-case each token (first char upper, rest
    lower; empty tokens stay empty), rejoin with '-'.
    """
    if not isinstance(name, str) or not name:
        raise ValueError("header name must be a non-empty string")
    for c in name:
        if ord(c) < 0x20 or ord(c) == 0x7F:
            raise ValueError("control character in header name: %r" % c)
    return "-".join(
        (tok[0].upper() + tok[1:].lower()) if tok else tok
        for tok in name.split("-")
    )


def _scan_main(argv):
    if len(argv) != 4 or argv[1] != "scan":
        print("usage: python3 hdrnorm.py scan <in.json> <out.json>",
              file=sys.stderr)
        return 2
    with open(argv[2]) as f:
        names = json.load(f)["names"]
    results = []
    for n in names:
        try:
            results.append({"name": n, "ok": True,
                            "canonical": canonical_header(n)})
        except ValueError:
            results.append({"name": n, "ok": False, "canonical": None})
    with open(argv[3], "w") as f:
        json.dump({"results": results}, f, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(_scan_main(sys.argv))
PY
chmod +x "$MODULE"

# ---- 2. The gateway service using the normalizer ----
cat > "$GATEWAY" <<'PY'
"""Onyx Rudder webhook relay gateway (header-normalization surface)."""
import os
import sys

from flask import Flask, jsonify, request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hdrnorm import canonical_header  # noqa: E402

app = Flask(__name__)


def _bad(msg):
    return jsonify({"error": {"code": "bad_request", "message": msg}}), 400


@app.get("/api/v1/health")
def health():
    return jsonify({"status": "ok"})


@app.post("/api/v1/rewrite")
def rewrite():
    body = request.get_json(silent=True)
    if not isinstance(body, dict) or not isinstance(body.get("headers"), dict):
        return _bad("body must be an object with a 'headers' object")
    out = {}
    try:
        for name, value in body["headers"].items():
            out[canonical_header(name)] = value
    except ValueError as e:
        return _bad("rejected header name: %s" % e)
    return jsonify({"rewritten": out})


@app.post("/api/v1/validate")
def validate():
    body = request.get_json(silent=True)
    if not isinstance(body, dict) or not isinstance(body.get("names"), list):
        return _bad("body must be an object with a 'names' list")
    results = []
    for n in body["names"]:
        try:
            results.append({"name": n, "ok": True,
                            "canonical": canonical_header(n)})
        except ValueError:
            results.append({"name": n, "ok": False, "canonical": None})
    return jsonify({"results": results})


@app.errorhandler(404)
def not_found(_e):
    return jsonify({"error": {"code": "not_found",
                              "message": "no such route"}}), 404


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8200
    app.run(host="127.0.0.1", port=port, threaded=True)
PY
chmod +x "$GATEWAY"

# ---- 3. Batch scan deliverable ----
python3 "$MODULE" scan "$SCAN_IN" "$REPORT"

echo "solve.sh done -> $MODULE, $GATEWAY and $REPORT"
ls -l "$MODULE" "$GATEWAY" "$REPORT"
