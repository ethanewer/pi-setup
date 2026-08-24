#!/bin/bash
# Oracle solution for item-033-main.
set -euo pipefail

cat > /app/server.py <<'PYEOF'
import json
import os
import sys

from transformers import AutoTokenizer

PORT = int(os.environ.get("PORT", "5000"))
MODEL = "/app/model"

# Load offline, deterministically (no network), before serving.
tok = AutoTokenizer.from_pretrained(MODEL, local_files_only=True)

from flask import Flask, jsonify, request

app = Flask(__name__)


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/tokenize", methods=["POST"])
def tokenize():
    raw = request.get_data(as_text=True)
    if not raw or not raw.strip():
        return jsonify({"error": "empty body"}), 400
    try:
        payload = json.loads(raw)
    except Exception:
        return jsonify({"error": "invalid JSON"}), 400
    if not isinstance(payload, dict):
        return jsonify({"error": "expected JSON object"}), 400
    text = payload.get("text")
    if not isinstance(text, str) or text == "":
        return jsonify({"error": "text must be a non-empty string"}), 400
    add_special = bool(payload.get("add_special_tokens", True))
    enc = tok(text, add_special_tokens=add_special)
    ids = enc["input_ids"]
    tokens = tok.convert_ids_to_tokens(ids)
    return jsonify({"tokens": tokens, "ids": ids, "add_special_tokens": add_special})


if __name__ == "__main__":
    print("READY", flush=True)
    app.run(host="0.0.0.0", port=PORT)
PYEOF

cat > /app/client_test.py <<'PYEOF'
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

from transformers import AutoTokenizer

PORT = int(os.environ.get("PORT", "5000"))
MODEL = "/app/model"
tok = AutoTokenizer.from_pretrained(MODEL, local_files_only=True)
BASE = f"http://127.0.0.1:{PORT}"


def req(method, path, payload=None, raw=None):
    url = BASE + path
    data = None
    headers = {}
    if raw is not None:
        data = raw.encode()
        headers["Content-Type"] = "application/json"
    elif payload is not None:
        data = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    r = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=10) as resp:
            return resp.status, json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read().decode() or "{}")
        except Exception:
            body = {}
        return e.code, body


def wait_ready(timeout=90):
    end = time.time() + timeout
    while time.time() < end:
        try:
            code, _ = req("GET", "/health")
            if code == 200:
                return True
        except Exception:
            pass
        time.sleep(0.5)
    return False


def main():
    proc = subprocess.Popen(
        [sys.executable, "/app/server.py"],
        env={**os.environ, "PORT": str(PORT)},
        stdout=subprocess.DEVNULL,
        stdin=subprocess.DEVNULL,
    )
    health_ok = wait_ready()

    text = "hello world banana cherry total report"
    positive_ok = False
    neg_ok = False

    try:
        expected = tok.encode(text, add_special_tokens=True)
        code, res = req("POST", "/tokenize", {"text": text, "add_special_tokens": True})
        positive_ok = (code == 200 and res.get("ids") == expected and isinstance(res.get("tokens"), list))

        code2, _ = req("POST", "/tokenize", {"wrong": "x"})
        code3, _ = req("POST", "/tokenize", raw="{not valid json")
        neg_ok = (code2 == 400 and code3 == 400)
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()

    result = {
        "health_ok": health_ok,
        "positive": positive_ok,
        "negative": neg_ok,
        "checked_text": text,
    }
    with open("/app/api_results.json", "w") as f:
        json.dump(result, f)


if __name__ == "__main__":
    main()
PYEOF

python3 /app/client_test.py
echo "client done"