#!/bin/bash
# Verifier for item-033-main: boot the agent's server fresh and test it live.
mkdir -p /logs/verifier
if [ ! -f /app/server.py ]; then
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

score=$(python3 - <<'PYEOF'
import json, os, sys, time, subprocess, random, urllib.request, urllib.error

from transformers import AutoTokenizer

MODEL = "/app/model"
tok = AutoTokenizer.from_pretrained(MODEL, local_files_only=True)

PORT = random.randint(5600, 8800)
BASE = f"http://127.0.0.1:{PORT}"

proc = subprocess.Popen(
    [sys.executable, "/app/server.py"],
    env={**os.environ, "PORT": str(PORT)},
    stdout=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
)

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
        try: body = json.loads(e.read().decode() or "{}")
        except Exception: body = {}
        return e.code, body

ok = False
try:
    # readiness
    ready = False
    end = time.time() + 120
    while time.time() < end:
        try:
            c, _ = req("GET", "/health")
            if c == 200:
                ready = True
                break
        except Exception:
            pass
        time.sleep(0.5)

    if not ready:
        print("0", end="")
    else:
        checks = 0
        # positive: several distinct texts must tokenize correctly vs local model
        texts = ["hello world banana cherry", "apple silver gold report total",
                 "the quick brown fox jumps over the lazy dog", "e=mc^2 is physics",
                 "12345 abcde xyz"]
        positives = 0
        for t in texts:
            expected = tok.encode(t, add_special_tokens=True)
            code, res = req("POST", "/tokenize", {"text": t})
            if code == 200 and res.get("ids") == expected:
                positives += 1
            elif code == 200:
                # tolerant: matching only ids which is authoritative
                pass
        if positives == len(texts):
            checks += 1

        # add_special_tokens=false variant
        code_f, res_f = req("POST", "/tokenize", {"text": "apple", "add_special_tokens": False})
        expected_f = tok.encode("apple", add_special_tokens=False)
        if code_f == 200 and res_f.get("ids") == expected_f:
            checks += 1

        # negatives
        c1, _ = req("POST", "/tokenize", {"no_text_field": 1})
        c2, _ = req("POST", "/tokenize", raw="{invalid")
        c3, _ = req("POST", "/tokenize", {"text": 12345})
        if c1 == 400 and c2 == 400 and c3 == 400:
            checks += 1

        if checks == 3:
            ok = True

finally:
    try:
        proc.terminate()
        proc.wait(timeout=5)
    except Exception:
        try: proc.kill()
        except Exception: pass

print("1" if ok else "0", end="")
PYEOF
)
printf "%s" "$score" > /logs/verifier/reward.txt
echo "reward=$score"