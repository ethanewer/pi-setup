#!/usr/bin/env python3
"""Flintworks triage service (flint-hollow).

Flask HTTP service exposing POST /triage: accepts {"text": "<string>"} and
returns {"label": <str>, "confidence": {"urgent": f, "normal": f, "backlog": f}},
plus GET /health for readiness.

Deterministic rule-based classifier:
  - tokenize: lowercase, extract [a-z0-9]+ runs
  - count marker words per class
  - score(class) = 2*count(class) + 1
  - confidence(class) = round(score / total, 4)
  - label = argmax(score); ties broken by priority urgent > normal > backlog

Modes:
  python3 /app/app.py --serve [--port N]          # serve on 127.0.0.1 (default 5000)
  python3 /app/app.py --classify-file IN OUT      # list of texts -> list of results
"""
import json
import re
import sys

from flask import Flask, jsonify, request

URGENT_MARKERS = {"asap", "urgent", "outage", "critical", "blocked",
                  "immediately", "emergency"}
NORMAL_MARKERS = {"update", "review", "question", "draft", "reminder", "soon"}
BACKLOG_MARKERS = {"later", "someday", "eventually", "whenever", "backlog",
                   "deferred"}
LABELS = ("urgent", "normal", "backlog")  # tie-break priority order

TOKEN_RE = re.compile(r"[a-z0-9]+")


def classify(text):
    counts = {"urgent": 0, "normal": 0, "backlog": 0}
    for tok in TOKEN_RE.findall(text.lower()):
        if tok in URGENT_MARKERS:
            counts["urgent"] += 1
        elif tok in NORMAL_MARKERS:
            counts["normal"] += 1
        elif tok in BACKLOG_MARKERS:
            counts["backlog"] += 1
    scores = {k: 2 * counts[k] + 1 for k in LABELS}
    total = sum(scores.values())
    confidence = {k: round(scores[k] / total, 4) for k in LABELS}
    label = max(LABELS, key=lambda k: scores[k])  # ties keep first (urgent)
    return {"label": label, "confidence": confidence}


app = Flask(__name__)


@app.get("/health")
def health():
    return jsonify({"ok": True})


@app.post("/triage")
def triage():
    data = request.get_json(force=True, silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "body must be valid JSON"}), 400
    text = data.get("text")
    if not isinstance(text, str):
        return jsonify({"error": "field 'text' must be a string"}), 400
    return jsonify(classify(text))


def main(argv):
    if "--serve" in argv:
        port = 5000
        if "--port" in argv:
            port = int(argv[argv.index("--port") + 1])
        app.run(host="127.0.0.1", port=port, debug=False, use_reloader=False)
        return 0
    if "--classify-file" in argv:
        i = argv.index("--classify-file")
        in_path, out_path = argv[i + 1], argv[i + 2]
        with open(in_path, "r", encoding="utf-8") as fh:
            texts = json.load(fh)
        if not isinstance(texts, list):
            print("input must be a JSON list of strings", file=sys.stderr)
            return 2
        results = []
        for t in texts:
            if not isinstance(t, str):
                print("input entries must be strings", file=sys.stderr)
                return 2
            results.append({"text": t, **classify(t)})
        with open(out_path, "w", encoding="utf-8") as fh:
            json.dump(results, fh, indent=2)
            fh.write("\n")
        return 0
    print("usage: app.py --serve [--port N] | --classify-file IN OUT",
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
