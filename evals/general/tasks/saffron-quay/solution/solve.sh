#!/bin/bash
# Oracle for saffron-quay: write the /app/server.py program (the actual work),
# then RUN it in score mode on the visible fixture to produce /app/answer.json.
# Never reads /tests.
set -eu

SERVER="/app/server.py"
OUT="/app/answer.json"

cat > "$SERVER" <<'PY'
import json
import re
import sys

POSITIVE = {"love", "excellent", "amazing", "delight", "superb",
            "flawless", "recommend", "perfect"}
NEGATIVE = {"hate", "terrible", "awful", "disaster", "broken",
            "refund", "angry", "disappointing"}


def classify(text):
    """Deterministic lexicon classifier specified by the task contract."""
    tokens = re.findall(r"[a-z]+", text.lower())
    pos = sum(1 for t in tokens if t in POSITIVE)
    neg = sum(1 for t in tokens if t in NEGATIVE)
    if pos > neg:
        label = "positive"
    elif pos < neg:
        label = "negative"
    elif pos > 0 and neg > 0:
        label = "mixed"
    else:
        label = "neutral"
    wp = pos + 1
    wn = neg + 1
    wu = 1.0
    total = wp + wn + wu
    confidence = {
        "positive": round(wp / total, 6),
        "negative": round(wn / total, 6),
        "neutral": round(wu / total, 6),
    }
    return {"label": label, "confidence": confidence}


def build_app():
    from flask import Flask, jsonify, request

    app = Flask(__name__)

    @app.get("/health")
    def health():
        return jsonify({"status": "ok"})

    @app.post("/score")
    def score():
        if not request.is_json:
            return jsonify({"error": "bad-content-type"}), 400
        data = request.get_json(silent=True)
        if not isinstance(data, dict):
            return jsonify({"error": "missing-text"}), 400
        text = data.get("text")
        if not isinstance(text, str):
            return jsonify({"error": "missing-text"}), 400
        return jsonify(classify(text))

    return app


def run_score(in_path, out_path):
    results = []
    with open(in_path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if line.strip() == "":
                continue
            res = classify(line)
            results.append({"text": line, "label": res["label"],
                            "confidence": res["confidence"]})
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(results, fh, indent=2)


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "serve":
        port = int(sys.argv[2])
        app = build_app()
        app.run(host="127.0.0.1", port=port, threaded=True, use_reloader=False)
        return 0
    if len(sys.argv) >= 2 and sys.argv[1] == "score":
        run_score(sys.argv[2], sys.argv[3])
        return 0
    print("usage: server.py serve <port> | server.py score <input.txt> <output.json>",
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x "$SERVER"

# Run the produced program on the visible fixture to create the answer file.
python3 "$SERVER" score /app/reviews.txt "$OUT"

echo "solve.sh done -> $SERVER and $OUT"
ls -l "$SERVER" "$OUT"
