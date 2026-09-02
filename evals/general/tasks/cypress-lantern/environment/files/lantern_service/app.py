"""cypress-lantern beacon registry service (deterministic, offline)."""
import hashlib
import os

from flask import Flask, jsonify, request

PORT = int(os.environ.get("LANTERN_PORT", "8917"))


def load_beacons():
    path = os.path.join(os.path.dirname(__file__), "beacons.txt")
    with open(path, "r", encoding="utf-8") as fh:
        return {line.strip() for line in fh if line.strip()}


BEACONS = load_beacons()
app = Flask(__name__)


def challenge_for(beacon_id):
    return hashlib.sha256(("waxis:" + beacon_id).encode()).hexdigest()[:24]


def turn_for(challenge):
    return hashlib.sha256(("rotor:" + challenge).encode()).hexdigest()[:8]


def key_for(turn):
    return hashlib.sha256(("filament:" + turn).encode()).hexdigest()[:16]


def final_for(key):
    return "lamplit-" + hashlib.sha256(("beam:" + key).encode()).hexdigest()[:8]


@app.get("/api/announce")
def announce():
    return jsonify({"service": "cypress-lantern", "status": "ok",
                    "beacons": sorted(BEACONS)})


@app.get("/api/beacon/<beacon_id>/challenge")
def challenge(beacon_id):
    if beacon_id not in BEACONS:
        return jsonify({"error": "unknown beacon"}), 404
    ch = challenge_for(beacon_id)
    return jsonify({"beacon": beacon_id, "challenge": ch, "turn": turn_for(ch)})


@app.post("/api/beacon/<beacon_id>/light")
def light(beacon_id):
    if beacon_id not in BEACONS:
        return jsonify({"error": "unknown beacon"}), 404
    body = request.get_json(silent=True)
    if not isinstance(body, dict) or "turn" not in body or "key" not in body:
        return jsonify({"error": "malformed payload"}), 400
    ch = challenge_for(beacon_id)
    if body["turn"] != turn_for(ch):
        return jsonify({"error": "stale turn"}), 403
    if body["key"] != key_for(body["turn"]):
        return jsonify({"error": "rejected"}), 403
    return jsonify({"status": "lit", "beacon": beacon_id,
                    "final": final_for(body["key"])})


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=PORT, debug=False)
