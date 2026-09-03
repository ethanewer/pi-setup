"""Coordinator desk of the Tern Systems offsite stack.

Issues the planning phrase to the registered planner and runs the booking
desk that validates a finished plan against the group's hidden state.
"""
from flask import Flask, jsonify, request

from offsite_common import (
    ADMIN_TOKEN,
    BUDGET_EUR,
    PHRASE,
    PLANNER_ID,
    log_event,
    validate_plan,
)

MAX_BOOK_ATTEMPTS = 6

app = Flask("offsite-coordinator")
book_attempts = {"n": 0}


@app.get("/health")
def health():
    return jsonify({"status": "ok", "service": "coordinator"})


@app.post("/phrase")
def phrase():
    body = request.get_json(silent=True) or {}
    pid = str(body.get("planner_id", "")).strip()
    if pid == PLANNER_ID:
        log_event("coordinator", "desk", "phrase_issued")
        return jsonify({"status": "ok", "phrase": PHRASE,
                        "budget_eur": BUDGET_EUR})
    log_event("coordinator", "desk", "phrase_denied")
    return jsonify({"status": "denied",
                    "reply": "You are not on the planner list."})


@app.post("/book")
def book():
    body = request.get_json(silent=True)
    admin = request.headers.get("X-Offsite-Admin", "") == ADMIN_TOKEN

    if body is None:
        return jsonify({"status": "rejected",
                        "reply": "The booking desk needs a JSON plan."}), 400

    if not admin:
        if book_attempts["n"] >= MAX_BOOK_ATTEMPTS:
            log_event("coordinator", "desk", "book_locked")
            return jsonify({"status": "locked",
                            "reply": "The booking desk has closed for the "
                                     "day. Six submissions is the limit."})
        book_attempts["n"] += 1

    ok, reason = validate_plan(body)
    if ok:
        log_event("coordinator", "desk", "book_ok")
        return jsonify({"status": "booked",
                        "reply": "Booked. See everyone there."})
    log_event("coordinator", "desk", "book_rejected:%s" % reason)
    payload = {"status": "rejected",
               "reply": "That plan does not work for the group."}
    if admin:
        payload["reason"] = reason
    return jsonify(payload)


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8701, debug=False, use_reloader=False)
