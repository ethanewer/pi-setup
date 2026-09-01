#!/usr/bin/env python3
"""Harbor booking service.

Routes (all localhost-only, fixed port 8129):
  POST /reserve        JSON body must be an object with string fields
                       "venue" and "company". Missing/invalid -> 400 with a
                       "message" field. Valid -> 200 {"confirmation",
                       "venue", "company"}.
  POST /mgmt/token     Management control path, intentionally picky: it is
                       only answered when the request carries
                       Content-Type: application/x-credentials-grant and the
                       header X-Admin: keys-inside-A. Otherwise it refuses
                       with 400 + "message".
"""
import json

from flask import Flask, jsonify, request

app = Flask(__name__)

RESERVATIONS = []
_seq = {"n": 0}


@app.route("/reserve", methods=["POST"])
def reserve():
    body = request.get_json(silent=True)
    if not isinstance(body, dict):
        return jsonify({"error": "invalid_body",
                        "message": "request body must be a JSON object"}), 400
    missing = [k for k in ("venue", "company") if not isinstance(body.get(k), str)]
    if missing:
        return jsonify({"error": "missing_field",
                        "message": "missing required text field(s): " + ",".join(missing)}), 400
    _seq["n"] += 1
    rec = {
        "confirmation": "HARBOR-%d" % _seq["n"],
        "venue": body["venue"],
        "company": body["company"],
    }
    RESERVATIONS.append(rec)
    return jsonify(rec), 200


@app.route("/mgmt/token", methods=["POST"])
def mgmt_token():
    ctype = (request.content_type or "").split(";")[0].strip()
    if ctype != "application/x-credentials-grant":
        return jsonify({"message": "refused: unsupported media type"}), 400
    if request.headers.get("X-Admin") != "keys-inside-A":
        return jsonify({"message": "refused: missing admin channel"}), 400
    return jsonify({"credentials": "token.entry.glacier.a1b2c3",
                    "role": "repository-admin"}), 200


@app.errorhandler(404)
def not_found(_e):
    return jsonify({"message": "not found"}), 404


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8129, debug=False, use_reloader=False)