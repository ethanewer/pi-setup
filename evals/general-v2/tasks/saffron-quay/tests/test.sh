#!/bin/bash
# Verifier for saffron-quay: enforces the no-modify rule on /app/reviews.txt,
# EXECUTES the deliverable program (/app/server.py) in score mode on the
# visible case and in serve mode against every hidden case under /tests/hidden,
# and checks the /app/answer.json deliverable. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixture (the instruction forbids
# modifying it; tampering defeats the visible-case check).
PRISTINE_REVIEWS_SHA="552335f1d3400359a12a347f82c2290d5a8d76cb889e367de56f130385866f14"

no_modify_broken=0
if [ ! -f /app/reviews.txt ]; then
    echo "no-modify: /app/reviews.txt missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/reviews.txt | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_REVIEWS_SHA" ]; then
        echo "no-modify: /app/reviews.txt was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys, time, urllib.request, urllib.error

SERVER = "/app/server.py"
PORT = 8741
BASE = "http://127.0.0.1:%d" % PORT
no_modify_broken = int(sys.argv[1])
failures = []

if no_modify_broken:
    failures.append("visible input modified or missing (no-modify rule)")


def close_conf(a, b, tol=2e-6):
    if set(a.keys()) != set(b.keys()):
        return False
    for k in a:
        try:
            if abs(float(a[k]) - float(b[k])) > tol:
                return False
        except Exception:
            return False
    return True


def norm_batch(obj):
    assert isinstance(obj, list), "expected a JSON array"
    out = []
    for item in obj:
        assert isinstance(item, dict), item
        assert set(item.keys()) == {"text", "label", "confidence"}, item
        assert isinstance(item["text"], str) and isinstance(item["label"], str)
        out.append((item["text"], item["label"], item["confidence"]))
    return out


if not os.path.isfile(SERVER):
    failures.append("missing /app/server.py")
    print("verify failures:", failures)
    sys.exit(1)

# --- score mode on the visible fixture, compared against /tests/expected.json
tmp_out = "/tmp/saffron_quay_visible.json"
if os.path.exists(tmp_out):
    os.remove(tmp_out)
try:
    r = subprocess.run([sys.executable, SERVER, "score", "/app/reviews.txt", tmp_out],
                       capture_output=True, text=True, timeout=120)
except Exception as e:
    r = None
    failures.append("score mode crashed: %s" % e)
if r is not None:
    if r.returncode != 0 or not os.path.exists(tmp_out):
        failures.append("score mode failed (rc=%s)" % r.returncode)
    else:
        try:
            with open(tmp_out) as f:
                got = norm_batch(json.load(f))
            with open("/tests/expected.json") as f:
                want = norm_batch(json.load(f))
            if len(got) != len(want):
                failures.append("visible batch length mismatch")
            else:
                for g, w in zip(got, want):
                    if g[0] != w[0] or g[1] != w[1] or not close_conf(g[2], w[2]):
                        failures.append("visible batch entry mismatch: %r" % (g,))
                        break
        except Exception as e:
            failures.append("visible batch output unreadable: %s" % e)

# --- /app/answer.json deliverable must match the visible expected
if os.path.isfile("/app/answer.json"):
    try:
        with open("/app/answer.json") as f:
            got = norm_batch(json.load(f))
        with open("/tests/expected.json") as f:
            want = norm_batch(json.load(f))
        if len(got) != len(want):
            failures.append("answer.json length mismatch")
        else:
            for g, w in zip(got, want):
                if g[0] != w[0] or g[1] != w[1] or not close_conf(g[2], w[2]):
                    failures.append("answer.json entry mismatch: %r" % (g,))
                    break
    except Exception as e:
        failures.append("answer.json unreadable: %s" % e)
else:
    failures.append("missing /app/answer.json")

# --- serve mode: start the HTTP service and run hidden cases against it
proc = subprocess.Popen([sys.executable, SERVER, "serve", str(PORT)],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
ready = False
try:
    deadline = time.time() + 40
    while time.time() < deadline:
        if proc.poll() is not None:
            break
        try:
            with urllib.request.urlopen(BASE + "/health", timeout=2) as resp:
                if resp.status == 200:
                    ready = True
                    break
        except Exception:
            time.sleep(0.4)
    if not ready:
        failures.append("server did not become healthy on /health")
    else:
        hidden_dir = "/tests/hidden"
        cases = sorted(os.listdir(hidden_dir)) if os.path.isdir(hidden_dir) else []
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            spec_path = os.path.join(base, "case.json")
            if not os.path.isfile(spec_path):
                failures.append("hidden '%s' malformed" % c)
                continue
            try:
                with open(spec_path) as f:
                    spec = json.load(f)
            except Exception as e:
                failures.append("hidden '%s' unreadable: %s" % (c, e))
                continue
            body = spec["body"]
            if isinstance(body, str):
                payload = body.encode("utf-8")
            else:
                payload = json.dumps(body).encode("utf-8")
            req = urllib.request.Request(
                BASE + "/score", data=payload, method="POST",
                headers={"Content-Type": spec.get("content_type", "application/json")})
            try:
                with urllib.request.urlopen(req, timeout=10) as resp:
                    status = resp.status
                    raw = resp.read()
            except urllib.error.HTTPError as e:
                status = e.code
                raw = e.read()
            except Exception as e:
                failures.append("hidden '%s' request failed: %s" % (c, e))
                continue
            if status != spec.get("expect_status", 200):
                failures.append("hidden '%s': status %s != %s" % (c, status, spec.get("expect_status")))
                continue
            try:
                got = json.loads(raw.decode("utf-8"))
            except Exception as e:
                failures.append("hidden '%s': response not JSON: %s" % (c, e))
                continue
            if spec.get("expect_status") == 400:
                if got != {"error": spec.get("error")}:
                    failures.append("hidden '%s': error body mismatch: %r" % (c, got))
            else:
                if not isinstance(got, dict) or set(got.keys()) != {"label", "confidence"}:
                    failures.append("hidden '%s': schema mismatch: %r" % (c, got))
                elif got["label"] != spec.get("label"):
                    failures.append("hidden '%s': label %r != %r" % (c, got["label"], spec.get("label")))
                elif not close_conf(got["confidence"], spec.get("confidence", {})):
                    failures.append("hidden '%s': confidence mismatch: %r" % (c, got["confidence"]))
finally:
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
