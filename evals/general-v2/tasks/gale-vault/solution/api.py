#!/usr/bin/env python3
"""Gale Vault API HTTP service — hardened implementation.

* canonical_header  : hardens header-name canonicalization (CWE-113) — rejects
  control characters (ord<0x20 or 0x7f) and blank/non-string names by raising
  ValueError, while preserving the canonical title form for benign names.
* POST /api/v1/notes validates every request field; a header key containing
  control characters -> HTTP 400 structured error.
* GET  /api/v1/notes?limit=<uint> — limit REQUIRED; missing / non-integer /
  negative => HTTP 400.
* GET  /api/v1/notes/<id>            — 400 for non-positive-int id, 404 with
  the offending id for a well-formed-but-missing note.
* GET  /api/v1/notes/<id>/render     — text/html; body served only through
  sanitizer.sanitize (stored-XSS CWE-79 is reported / evidenced by xss.html).
* GET  /api/v1/doc.json              — services /app/schema.json verbatim.
"""
import json
import re
import sys

import sanitizer

from flask import Flask, jsonify, request

_SCHEMA_PATH = "/app/schema.json"


def canonical_header(name):
    """Validate and canonicalize a single HTTP header name.

    Raises ValueError for blank/non-string names or any control character
    (ord < 0x20 or 0x7f); otherwise returns the canonical title form.
    """
    if not isinstance(name, str) or name == "":
        raise ValueError("invalid header name")
    if any(ord(c) < 0x20 or ord(c) == 0x7f for c in name):
        raise ValueError("control character in header name")
    return "-".join((t[:1].upper() + t[1:].lower()) if t else ""
                    for t in name.split("-"))


app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 512 * 1024

NOTES = []
_seq = [0]


def _next_id():
    _seq[0] += 1
    return _seq[0]


def _push(title, headers, body, tags):
    rec = {"id": _next_id(), "title": title, "headers": headers,
           "body": body, "tags": tags}
    NOTES.append(rec)
    return rec


def _find(i):
    for n in NOTES:
        if n["id"] == i:
            return n
    return None


def _valid_id(s):
    return isinstance(s, str) and re.fullmatch(r"[1-9][0-9]*", s) is not None


def _err(code, message):
    return jsonify({"error": {"code": code, "message": message}})


def _full_schema():
    try:
        with open(_SCHEMA_PATH, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {"name": "Gale Vault", "error": "schema unreadable"}


@app.get("/api/v1/doc.json")
def api_doc():
    return app.response_class(json.dumps(_full_schema(), sort_keys=True),
                              mimetype="application/json")


@app.post("/api/v1/notes")
def create_note():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return _err("bad_request", "request body must be a JSON object"), 400
    title = data.get("title")
    body = data.get("body")
    if not isinstance(title, str) or title.strip() == "":
        return _err("bad_request", "'title' must be a non-empty string"), 400
    if not isinstance(body, str):
        return _err("bad_request", "'body' must be a string"), 400
    tags = data.get("tags", [])
    if not isinstance(tags, list) or not all(isinstance(t, str) for t in tags):
        return _err("bad_request", "'tags' must be an array of strings"), 400
    header_in = data.get("header", {})
    if not isinstance(header_in, dict):
        return _err("bad_request", "'header' must be an object"), 400
    canon = {}
    for k, v in header_in.items():
        try:
            ck = canonical_header(k)
        except ValueError:
            return _err("bad_request", "invalid header name: %r" % k), 400
        if not isinstance(v, str):
            return _err("bad_request", "header value must be a string"), 400
        canon[ck] = v
    rec = _push(title, canon, body, tags)
    return jsonify({"id": rec["id"], "title": rec["title"]}), 201


@app.get("/api/v1/notes")
def list_notes():
    rl = request.args.get("limit")
    if rl is None or re.fullmatch(r"[0-9]+", rl) is None:
        return _err("bad_request", "'limit' must be a non-negative integer"), 400
    limit = int(rl)
    sel = NOTES[:limit]
    return jsonify({
        "count": len(sel),
        "notes": [{"id": n["id"], "title": n["title"], "tags": n["tags"],
                   "headers": list(n["headers"].keys())} for n in sel],
    }), 200


@app.get("/api/v1/notes/<id>")
def note_detail(id):
    if not _valid_id(id):
        return _err("bad_request", "note id must be a positive integer"), 400
    n = _find(int(id))
    if n is None:
        return jsonify({"error": {"code": "not_found", "id": int(id),
                                  "message": "no such note"}}), 404
    return jsonify({"id": n["id"], "title": n["title"], "headers": n["headers"],
                    "tags": n["tags"], "body": n["body"]}), 200


@app.get("/api/v1/notes/<id>/render")
def render(id):
    if not _valid_id(id):
        return _err("bad_request", "note id must be a positive integer"), 400
    n = _find(int(id))
    if n is None:
        return jsonify({"error": {"code": "not_found", "id": int(id),
                                  "message": "no such note"}}), 404
    html = sanitizer.sanitize(n["body"])
    return (html, 200, {"Content-Type": "text/html; charset=utf-8"})


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8031
    print("Gale Vault API on 127.0.0.1:%d" % port, flush=True)
    app.run(host="127.0.0.1", port=port, threaded=True)