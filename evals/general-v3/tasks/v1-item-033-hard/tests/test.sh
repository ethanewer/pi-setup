#!/bin/bash
# Verifier for item-033-hard.
mkdir -p /logs/verifier
if [ ! -f /app/server.py ]; then
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

score=$(python3 - <<'PYEOF'
import json, os, sys, time, subprocess, random, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor
from transformers import AutoTokenizer

MODEL = "/app/model"
tok = AutoTokenizer.from_pretrained(MODEL, local_files_only=True)

PORT = random.randint(5600, 8800)
BASE = f"http://127.0.0.1:{PORT}"

proc = subprocess.Popen([sys.executable, "/app/server.py"],
                        env={**os.environ, "PORT": str(PORT)},
                        stdout=subprocess.DEVNULL, stdin=subprocess.DEVNULL)

def req(method, path, payload=None, raw=None):
    data = None; headers = {}
    if raw is not None:
        data = raw.encode(); headers["Content-Type"] = "application/json"
    elif payload is not None:
        data = json.dumps(payload).encode(); headers["Content-Type"] = "application/json"
    r = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=15) as resp:
            return resp.status, json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        try: body = json.loads(e.read().decode() or "{}")
        except Exception: body = {}
        return e.code, body

marks = []
try:
    ready = False
    end = time.time() + 150
    while time.time() < end:
        try:
            if req("GET", "/health")[0] == 200:
                ready = True
                break
        except Exception:
            pass
        time.sleep(0.5)
    if not ready:
        marks.append("health")
    else:
        # model revision metadata matches model_meta.json
        try:
            meta = json.load(open("/app/model/model_meta.json"))
            c, body = req("GET", "/model")
            if c == 200 and body.get("loaded_revision") == meta.get("revision") and body.get("offline"):
                marks.append("revision")
        except Exception:
            pass

        # single positive on several texts
        texts = ["hello world banana cherry", "apple silver gold", "the quick brown fox jumps",
                 "e2e test pipeline", "12345 abcde"]
        single_ok = True
        for t in texts:
            c, body = req("POST", "/tokenize", {"text": t})
            if c != 200 or body.get("ids") != tok.encode(t, add_special_tokens=True):
                single_ok = False
        if single_ok:
            marks.append("single")

        # batch positive
        code, res = req("POST", "/batch", {"texts": texts})
        if code == 200 and len(res.get("results", [])) == len(texts) and all(
                r["ids"] == tok.encode(r["text"], add_special_tokens=True) for r in res["results"]):
            marks.append("batch")

        # truncation
        c2, res2 = req("POST", "/batch", {"texts": texts, "max_length": 4, "truncation": True})
        if c2 == 200 and all(
                len(r["ids"]) <= 4 and r["ids"] == tok.encode(r["text"], add_special_tokens=True)[:4]
                for r in res2.get("results", [])):
            marks.append("truncation")

        # negatives
        neg_codes = [
            req("POST", "/tokenize", {"nope": 1})[0],
            req("POST", "/batch", {"nope": []})[0],
            req("POST", "/batch", {"texts": []})[0],
            req("POST", "/tokenize", raw="{{broken")[0],
            req("POST", "/tokenize", {"text": 42})[0],
            req("POST", "/batch", {"texts": ["ok"], "max_length": -3})[0],
        ]
        if all(x == 400 for x in neg_codes):
            marks.append("negative")

        # concurrency: overlapping identical + distinct requests
        pool = [f"thread payload number {i} with some long text" for i in range(24)]

        def one(t):
            c, b = req("POST", "/batch", {"texts": [t]})
            return c == 200 and b.get("results") and b["results"][0]["ids"] == tok.encode(t, add_special_tokens=True)

        with ThreadPoolExecutor(max_workers=8) as ex:
            results = list(ex.map(one, pool))
        if all(results):
            marks.append("concurrency")
finally:
    try:
        proc.terminate(); proc.wait(timeout=6)
    except Exception:
        try: proc.kill()
        except Exception: pass

# reward scoring
total = 7
got = 0
allmarks = ["health","revision","single","batch","truncation","negative","concurrency"]
for m in allmarks:
    if m in marks:
        got += 1
score = 0.0
if got == total:
    score = 1.0
elif got >= 6:
    score = 0.8
elif got >= 5:
    score = 0.6
elif got >= 4:
    score = 0.4
elif got >= 3:
    score = 0.25
print(f"{score:.2f}", end="")
PYEOF
)
printf "%s" "$score" > /logs/verifier/reward.txt
echo "reward=$score"