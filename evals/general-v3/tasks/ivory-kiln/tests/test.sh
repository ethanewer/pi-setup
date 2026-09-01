#!/bin/bash
# Verifier for ivory-kiln: checks the visible-case deliverables are present and
# correct, ENFORCES the no-modify rule on the supplied /app fixtures, and
# EXECUTES the deliverable program (/app/solve.py) on the visible photograph
# and on every hidden photograph in /tests/hidden, comparing the transcribed
# value exactly. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures in /app (the instruction
# tells the agent not to modify these; tampering defeats the visible check).
PRISTINE_PHOTO_SHA="58d189809bd7da136d842c8346ce65a214a0f96f3492535b063fc0822550e58e"
PRISTINE_CALIB_SHA="1b209c6e1a4e871c33c556995ec54a5f80d7ac26317db188d852690245638924"

no_modify_broken=0
if [ ! -f /app/code.png ]; then
    echo "no-modify: /app/code.png missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/code.png | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_PHOTO_SHA" ]; then
        echo "no-modify: /app/code.png was modified" >&2
        no_modify_broken=1
    fi
fi
if [ ! -f /app/calib.json ]; then
    echo "no-modify: /app/calib.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/calib.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_CALIB_SHA" ]; then
        echo "no-modify: /app/calib.json was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/solve.py"
no_modify_broken = int(sys.argv[1])

failures = []
if no_modify_broken:
    failures.append("visible fixtures modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")
    failures.append("missing /app/answer.json")
else:
    def run_case(photo, calib, expected_path):
        out = "/tmp/ivory_kiln_verify_out.json"
        if os.path.exists(out):
            os.remove(out)
        try:
            r = subprocess.run(
                [sys.executable, SOLVE, photo, calib, out],
                capture_output=True, text=True, timeout=120,
            )
        except Exception as e:
            return "exec error: %s" % e
        if r.returncode != 0:
            return "rc=%s stderr=%r" % (r.returncode, (r.stderr or "")[-200:])
        if not os.path.exists(out):
            return "no output file written"
        try:
            with open(out) as f:
                got = json.load(f)
            with open(expected_path) as f:
                want = json.load(f)
        except Exception as e:
            return "output unreadable: %s" % e
        if not (isinstance(got, dict) and set(got) == {"code_value"}):
            return "output must be a JSON object with exactly key 'code_value'"
        gv, wv = got["code_value"], want["code_value"]
        if not (isinstance(gv, int) and not isinstance(gv, bool)):
            return "code_value must be an int, got %r" % (gv,)
        if gv != wv:
            return "value %r != expected %r" % (gv, wv)
        return None

    # --- visible case: EXECUTE solve.py on the supplied photograph ---
    if not (os.path.isfile("/app/code.png") and os.path.isfile("/app/calib.json")):
        failures.append("visible fixtures missing")
    else:
        err = run_case("/app/code.png", "/app/calib.json", "/tests/expected.json")
        if err:
            failures.append("visible case failed: %s" % err)

    # --- visible-case deliverable: /app/answer.json must match the visible
    #     photograph's expected value ---
    if os.path.isfile("/app/answer.json"):
        try:
            with open("/app/answer.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if not (isinstance(got, dict) and got.get("code_value") == want["code_value"]):
                failures.append("answer.json does not match visible expected")
        except Exception:
            failures.append("answer.json unreadable")
    else:
        failures.append("missing /app/answer.json")

    # --- hidden cases: GENUINELY distinct photographs with their own
    #     constants and calibrations ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            photo = os.path.join(base, "code.png")
            calib = os.path.join(base, "calib.json")
            exp = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in (photo, calib, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            err = run_case(photo, calib, exp)
            if err:
                failures.append("hidden case '%s' failed: %s" % (c, err))
    else:
        failures.append("no hidden cases present")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
