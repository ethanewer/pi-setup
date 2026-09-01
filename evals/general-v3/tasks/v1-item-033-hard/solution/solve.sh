#!/bin/bash
# Oracle solution for item-033-hard.
set -euo pipefail

cat > /app/server.py <<'PYEOF'
import json
import os

from transformers import AutoTokenizer

PORT = int(os.environ.get("PORT", "5000"))
MODEL = "/app/model"
with open("/app/model/model_meta.json") as f:
    META = json.load(f)

tok = AutoTokenizer.from_pretrained(MODEL, local_files_only=True)

from flask import Flask, jsonify, request

app = Flask(__name__)


def read_body():
    raw = request.get_data(as_text=True)
    if not raw or not raw.strip():
        return None, "empty body"
    try:
        p = json.loads(raw)
    except Exception:
        return None, "invalid JSON"
    if not isinstance(p, dict):
        return None, "expected JSON object"
    return p, None


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/model")
def model():
    out = dict(META)
    out["offline"] = True
    out["loaded_revision"] = META.get("revision")
    return jsonify(out)


@app.route("/tokenize", methods=["POST"])
def tokenize():
    payload, err = read_body()
    if err:
        return jsonify({"error": err}), 400
    text = payload.get("text")
    if not isinstance(text, str) or text == "":
        return jsonify({"error": "text must be a non-empty string"}), 400
    add_special = bool(payload.get("add_special_tokens", True))
    enc = tok(text, add_special_tokens=add_special)
    ids = list(enc["input_ids"])
    tokens = tok.convert_ids_to_tokens(ids)
    return jsonify({"text": text, "tokens": tokens, "ids": ids, "add_special_tokens": add_special})


@app.route("/batch", methods=["POST"])
def batch():
    payload, err = read_body()
    if err:
        return jsonify({"error": err}), 400
    texts = payload.get("texts")
    if not isinstance(texts, list) or len(texts) == 0:
        return jsonify({"error": "texts must be a non-empty list"}), 400
    if not all(isinstance(x, str) and x.strip() != "" for x in texts):
        return jsonify({"error": "texts must contain non-empty strings"}), 400
    add_special = bool(payload.get("add_special_tokens", True))
    max_length = payload.get("max_length")
    truncation = bool(payload.get("truncation", True))
    if max_length is not None:
        if not isinstance(max_length, int) or isinstance(max_length, bool) or max_length <= 0:
            return jsonify({"error": "max_length must be a positive integer"}), 400
    results = []
    for t in texts:
        enc = tok(t, add_special_tokens=add_special)
        ids = list(enc["input_ids"])
        tokens = tok.convert_ids_to_tokens(ids)
        if truncation and max_length is not None:
            ids = ids[:max_length]
            tokens = tokens[:max_length]
        results.append({"text": t, "tokens": tokens, "ids": ids})
    return jsonify({"results": results, "count": len(results)})


if __name__ == "__main__":
    print("READY", flush=True)
    app.run(host="0.0.0.0", port=PORT)
PYEOF

cat > /app/client_test.py <<'PYEOF'
import json
import os
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

from transformers import AutoTokenizer

PORT = int(os.environ.get("PORT", "5000"))
MODEL = "/app/model"
tok = AutoTokenizer.from_pretrained(MODEL, local_files_only=True)
BASE = f"http://127.0.0.1:{PORT}"


def req(method, path, payload=None, raw=None):
    data = None
    headers = {}
    if raw is not None:
        data = raw.encode(); headers["Content-Type"] = "application/json"
    elif payload is not None:
        data = json.dumps(payload).encode(); headers["Content-Type"] = "application/json"
    r = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=15) as resp:
            return resp.status, json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read().decode() or "{}")
        except Exception:
            body = {}
        return e.code, body


def wait_ready(timeout=120):
    end = time.time() + timeout
    while time.time() < end:
        try:
            c, _ = req("GET", "/health")
            if c == 200:
                return True
        except Exception:
            pass
        time.sleep(0.5)
    return False


def main():
    proc = subprocess.Popen([sys.executable, "/app/server.py"],
                            env={**os.environ, "PORT": str(PORT)},
                            stdout=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
    try:
        health_ok = wait_ready()

        # model revision
        rev_ok = False
        try:
            c, body = req("GET", "/model")
            if c == 200 and body.get("loaded_revision") == body.get("revision"):
                rev_ok = True
        except Exception:
            pass

        # single positive
        texts = ["hello world banana report", "apple cherry silver", "the quick brown fox"]
        single_ok = all(
            req("POST", "/tokenize", {"text": t})[0] == 200 and
            req("POST", "/tokenize", {"text": t})[1].get("ids") == tok.encode(t, add_special_tokens=True)
            for t in texts
        )

        # batch positive
        code, res = req("POST", "/batch", {"texts": texts})
        batch_ok = code == 200 and len(res.get("results", [])) == len(texts) and all(
            r["ids"] == tok.encode(r["text"], add_special_tokens=True) for r in res["results"]
        )

        # truncation
        code_t, res_t = req("POST", "/batch", {"texts": texts, "max_length": 4, "truncation": True})
        trunc_ok = code_t == 200 and all(
            len(r["ids"]) <= 4 and r["ids"] == tok.encode(r["text"], add_special_tokens=True)[:4]
            for r in res_t.get("results", [])
        )

        # negative
        neg = [
            req("POST", "/tokenize", {"wrong": 1})[0],
            req("POST", "/batch", {"wrong": []})[0],
            req("POST", "/batch", {"texts": []})[0],
            req("POST", "/tokenize", raw="{bad")[0],
            req("POST", "/tokenize", {"text": 123})[0],
        ]
        neg_ok = all(x == 400 for x in neg)

        # concurrency
        pool_texts = [f"item number {i} plus more words to tokenize" for i in range(24)]

        def one(t):
            c, body = req("POST", "/tokenize", {"text": t})
            return c == 200 and body.get("ids") == tok.encode(t, add_special_tokens=True)

        concur_ok = True
        with ThreadPoolExecutor(max_workers=6) as ex:
            futs = [ex.submit(one, t) for t in pool_texts]
            for f in futs:
                if not f.result():
                    concur_ok = False

        result = {
            "health_ok": health_ok,
            "model_revision": rev_ok,
            "single_pos": single_ok,
            "batch_pos": batch_ok,
            "truncation": trunc_ok,
            "negative": neg_ok,
            "concurrency": concur_ok,
        }
        if "" == "":
            pass
        with open("/app/batch_results.json", "w") as f:
            json.dump(result, f)
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=8)
        except Exception:
            proc.kill()


if __name__ == "__main__":
    main()
PYEOF

python3 /app/client_test.py
echo "hard client done"