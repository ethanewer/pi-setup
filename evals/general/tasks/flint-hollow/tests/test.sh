#!/bin/bash
# Verifier for flint-hollow: EXECUTES the deliverable /app/app.py twice —
# once as a live Flask server (POSTing visible + hidden requests to /triage)
# and once in batch mode — and checks the /app/answer.json deliverable.
# Writes REWARD (0/1) to /logs/verifier/reward.txt. All parses guarded.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import glob
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

APP = "/app/app.py"
ANSWER = "/app/answer.json"
PORT = 5831
URL = "http://127.0.0.1:%d" % PORT
failures = []


def post(raw_body, path="/triage", timeout=30):
    req = urllib.request.Request(
        URL + path, data=raw_body.encode("utf-8"),
        headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode("utf-8", "replace"), resp.headers.get("Content-Type", "")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace"), e.headers.get("Content-Type", "")


def parse_body(raw):
    try:
        return json.loads(raw)
    except Exception:
        return None


# ---------------- start the live server (executes /app/app.py) ----------------
if not os.path.isfile(APP):
    print("verify failures: missing /app/app.py")
    sys.exit(1)

proc = None
try:
    proc = subprocess.Popen(
        [sys.executable, APP, "--serve", "--port", str(PORT)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
except Exception as e:
    print("verify failures: could not start /app/app.py: %r" % e)
    sys.exit(1)

ready = False
deadline = time.time() + 60
while time.time() < deadline:
    if proc.poll() is not None:
        failures.append("/app/app.py --serve exited early rc=%s" % proc.returncode)
        break
    try:
        with urllib.request.urlopen(URL + "/health", timeout=5) as r:
            if json.loads(r.read()) == {"ok": True}:
                ready = True
                break
    except Exception:
        time.sleep(0.5)
if proc.poll() is None and not ready:
    failures.append("server never became healthy on /health")

# ---------------- visible fixture cases (live POSTs) ----------------
if ready:
    try:
        with open("/app/visible_cases.json") as fh:
            visible_texts = json.load(fh)
        if not isinstance(visible_texts, list) or not all(isinstance(t, str) for t in visible_texts):
            raise ValueError("visible fixture not a list of strings")
    except Exception as e:
        visible_texts = None
        failures.append("visible fixture unreadable: %r" % e)

    expected = None
    try:
        with open("/tests/expected.json") as fh:
            expected = json.load(fh)["cases"]
        if not isinstance(expected, list):
            raise ValueError("expected.json cases not a list")
    except Exception as e:
        failures.append("tests/expected.json unreadable: %r" % e)

    if visible_texts is not None and expected is not None:
        if len(visible_texts) != len(expected):
            failures.append("visible case count mismatch")
        else:
            for text, exp in zip(visible_texts, expected):
                status, raw, ctype = post(json.dumps({"text": text}))
                if status != 200 or not ctype.startswith("application/json"):
                    failures.append("visible POST status/ctype %s %r" % (status, ctype))
                    continue
                body = parse_body(raw)
                if body is None:
                    failures.append("visible POST unparseable body")
                    continue
                if body != {"label": exp["label"], "confidence": exp["confidence"]}:
                    failures.append("visible POST mismatch for %r: %r" % (text[:40], body))
                conf = body.get("confidence") if isinstance(body, dict) else None
                if not isinstance(conf, dict) or set(conf) != {"urgent", "normal", "backlog"}:
                    failures.append("visible POST bad confidence keys %r" % (conf,))
                elif body.get("label") != max(
                        ("urgent", "normal", "backlog"), key=lambda k: conf[k]):
                    failures.append("visible POST label is not argmax of confidence")

    # ---------------- hidden cases (live POSTs) ----------------
    hidden_dir = "/tests/hidden"
    cases = sorted(glob.glob(os.path.join(hidden_dir, "*"))) if os.path.isdir(hidden_dir) else []
    if len(cases) < 2:
        failures.append("fewer than 2 hidden cases")
    for cdir in cases:
        try:
            with open(os.path.join(cdir, "request.json")) as fh:
                spec = json.load(fh)
            raw_body = spec["raw_body"]
            exp_status = int(spec["expect_status"])
            exp_body = spec["expect_body"]
            if not isinstance(raw_body, str) or not isinstance(exp_body, dict):
                raise ValueError("bad spec shape")
        except Exception as e:
            failures.append("hidden %s unreadable: %r" % (os.path.basename(cdir), e))
            continue
        status, raw, _ = post(raw_body)
        if status != exp_status:
            failures.append("hidden %s status %d want %d" % (os.path.basename(cdir), status, exp_status))
            continue
        body = parse_body(raw)
        if body != exp_body:
            failures.append("hidden %s body %r want %r" % (os.path.basename(cdir), body, exp_body))
            continue
        if status == 200:
            conf = body.get("confidence") if isinstance(body, dict) else None
            if not isinstance(conf, dict) or set(conf) != {"urgent", "normal", "backlog"}:
                failures.append("hidden %s bad confidence keys" % os.path.basename(cdir))
            elif body.get("label") != max(
                    ("urgent", "normal", "backlog"), key=lambda k: conf[k]):
                failures.append("hidden %s label is not argmax of confidence" % os.path.basename(cdir))

    # ---------------- batch mode + answer.json deliverable ----------------
    out = "/tmp/flint_batch_out.json"
    try:
        r = subprocess.run(
            [sys.executable, APP, "--classify-file", "/app/visible_cases.json", out],
            capture_output=True, text=True, timeout=60)
        if r.returncode != 0:
            failures.append("batch mode rc=%d stderr=%s" % (r.returncode, r.stderr.strip()[:200]))
        else:
            with open(out) as fh:
                got = json.load(fh)
            with open("/tests/expected.json") as fh:
                want = json.load(fh)["cases"]
            if got != want:
                failures.append("batch-mode output differs from visible expected")
    except Exception as e:
        failures.append("batch mode failed: %r" % e)

    if os.path.isfile(ANSWER):
        try:
            with open(ANSWER) as fh:
                ans = json.load(fh)
            with open("/tests/expected.json") as fh:
                want = json.load(fh)["cases"]
            if ans != want:
                failures.append("/app/answer.json does not match visible expected")
        except Exception as e:
            failures.append("/app/answer.json unreadable: %r" % e)
    else:
        failures.append("missing /app/answer.json")
else:
    failures.append("skipping request checks: server not ready")

if proc is not None:
    try:
        proc.terminate()
        proc.wait(timeout=10)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
