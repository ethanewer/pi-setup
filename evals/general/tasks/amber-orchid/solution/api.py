"""Merkstock Index Ledger - hardened REST service.

Serves a synthetic blockchain index (from ledger.json), user comments (rendered
through the shared sanitizer), and token uploads (hardened against path
traversal). Run with:  python3 api.py [PORT]   (default 8039).
"""
import base64
import binascii
import json
import os
import re
import sys

from flask import Flask, Response, jsonify, request

import sanitizer

APP_DIR = os.path.dirname(os.path.abspath(__file__))
UPLOAD_DIR = os.path.join(APP_DIR, "uploads")

with open(os.path.join(APP_DIR, "ledger.json"), encoding="utf-8") as fh:
    LEDGER = json.load(fh)

CHAIN = {b["hash"]: b for b in LEDGER["blocks"]}
TXS = {t["id"]: t for t in LEDGER["txs"]}
MAX_HEIGHT = LEDGER["height"] - 1

with open(os.path.join(APP_DIR, "schema.json"), encoding="utf-8") as fh:
    SCHEMA = json.load(fh)

app = Flask(__name__)

comments = {}
_next_id = [1]


def _err(code, message, status):
    return jsonify({"error": {"code": code, "message": message}}), status


def _parse_height(raw):
    """Return the integer height if valid, else None (including 64-bit overflow)."""
    if raw is None or raw == "":
        return None
    if not raw.isdigit():
        return None
    try:
        n = int(raw)
    except (ValueError, OverflowError):
        return None
    if n < 0 or n > (1 << 63) - 1:
        return None
    return n


@app.route("/api/v1/health")
def health():
    return jsonify({"status": "ok"}), 200


@app.route("/api/v1/blocks", methods=["GET"])
def blocks():
    raw = request.args.get("height")
    if raw is None or raw == "":
        return _err("bad_request", "height is required and must be a non-negative integer", 400)
    n = _parse_height(raw)
    if n is None:
        return _err("bad_request", "height must be a non-negative base-10 integer", 400)
    if n > MAX_HEIGHT:
        return _err("not_found", "no such block", 404)
    return jsonify(LEDGER["blocks"][n]), 200


@app.route("/api/v1/blocks/<path:hashid>", methods=["GET"])
def block_by_hash(hashid):
    rec = CHAIN.get(hashid)
    if rec is None:
        return _err("not_found", "no such block", 404)
    return jsonify(rec), 200


@app.route("/api/v1/txs/<path:txid>", methods=["GET"])
def tx_by_id(txid):
    rec = TXS.get(txid)
    if rec is None:
        return _err("not_found", "no such transaction", 404)
    return jsonify(rec), 200


@app.route("/api/v1/uploads", methods=["POST"])
def upload():
    body = request.get_json(silent=True)
    if not isinstance(body, dict):
        return _err("bad_request", "expected a JSON object", 400)
    name = body.get("name")
    data_b64 = body.get("data")
    tokens = body.get("tokens")
    if not isinstance(name, str) or name == "":
        return _err("bad_request", "name must be a non-empty filename", 400)
    # Reject every path-traversal / unsafe form before touching the filesystem.
    unsafe = (
        name.startswith(".") or "/" in name or "\\" in name or ".." in name
        or any(c.isspace() for c in name)
        or any(ord(c) < 0x20 or ord(c) == 0x7F for c in name)
    )
    if unsafe:
        return _err("bad_request", "unsafe filename rejected", 400)
    if not isinstance(data_b64, str):
        return _err("bad_request", "data must be a base64 string", 400)
    if not isinstance(tokens, int) or isinstance(tokens, bool) or tokens < 0:
        return _err("bad_request", "tokens must be a non-negative integer", 400)
    try:
        payload = base64.b64decode(data_b64, validate=True)
    except (ValueError, binascii.Error):
        return _err("bad_request", "data is not valid base64", 400)

    safe = os.path.basename(name)
    if safe != name:
        return _err("bad_request", "unsafe filename rejected", 400)

    os.makedirs(UPLOAD_DIR, exist_ok=True)
    real_upload = os.path.realpath(UPLOAD_DIR)
    target = os.path.realpath(os.path.join(UPLOAD_DIR, safe))
    if not (target == real_upload or target.startswith(real_upload + os.sep)):
        return _err("bad_request", "unsafe filename rejected", 400)
    with open(target, "wb") as fh:
        fh.write(payload)
    return jsonify({"stored": safe, "size": len(payload)}), 201


@app.route("/api/v1/comments", methods=["POST"])
def add_comment():
    body = request.get_json(silent=True)
    if not isinstance(body, dict):
        return _err("bad_request", "expected a JSON object", 400)
    title = body.get("title")
    text = body.get("body")
    if not isinstance(title, str) or title == "":
        return _err("bad_request", "title must be a non-empty string", 400)
    if not isinstance(text, str) or text == "":
        return _err("bad_request", "body must be a non-empty string", 400)
    cid = _next_id[0]
    _next_id[0] += 1
    comments[cid] = {"id": cid, "title": title, "body": text}
    return jsonify({"id": cid}), 201


@app.route("/api/v1/comments/<path:cid>/render", methods=["GET"])
def render_comment(cid):
    if not re.fullmatch(r"[1-9][0-9]*", cid):
        return _err("bad_request", "id must be a positive integer", 400)
    rec = comments.get(int(cid))
    if rec is None:
        return _err("not_found", "no such comment", 404)
    safe = sanitizer.sanitize(rec["body"])
    html = ('<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"></head>'
            '<body>%s</body></html>') % safe
    return Response(html, status=200, content_type="text/html; charset=utf-8")


@app.route("/api/v1/doc.json", methods=["GET"])
def doc():
    return jsonify(SCHEMA), 200


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8039
    app.run(host="127.0.0.1", port=port, debug=False, use_reloader=False, threaded=True)
