#!/bin/bash
# Verifier for copper-quill: checks the visible-case deliverables are present
# and correct, ENFORCES the no-modify rule on the supplied /app inputs, and
# EXECUTES the deliverable program (/app/score.py) on the visible case and on
# every hidden case in /tests/hidden. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures in /app (the instruction
# tells the agent not to modify these; tampering defeats the visible check).
PRISTINE_MODEL_SHA="ef116325a1bf93fa82da6085efefae85046c390fa9ef0a5585e8994cfbe0d9e3"
PRISTINE_KEY_SHA="3200ceb3db7915757e14add122aee84640c4c6eaa943ce5c3487a934b082a1d7"

no_modify_broken=0
for pair in "/app/model.json:$PRISTINE_MODEL_SHA" "/app/key.json:$PRISTINE_KEY_SHA"; do
    path="${pair%%:*}"
    want="${pair##*:}"
    if [ ! -f "$path" ]; then
        echo "no-modify: $path missing" >&2
        no_modify_broken=1
    else
        actual="$(sha256sum "$path" | awk '{print $1}')"
        if [ "$actual" != "$want" ]; then
            echo "no-modify: $path was modified" >&2
            no_modify_broken=1
        fi
    fi
done

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/score.py"
REPORT = "/app/report.json"
no_modify_broken = int(sys.argv[1])


def norm(obj):
    """Normalize a report so dicts and rounded floats compare by content."""
    assert isinstance(obj, list), obj
    out = []
    for entry in obj:
        assert isinstance(entry, dict), entry
        assert set(entry.keys()) == {"round", "correct", "total", "accuracy"}, entry
        assert isinstance(entry["round"], str), entry
        c = entry["correct"]
        t = entry["total"]
        assert isinstance(c, int) and not isinstance(c, bool), entry
        assert isinstance(t, int) and not isinstance(t, bool), entry
        acc = entry["accuracy"]
        if acc is None:
            out.append((entry["round"], c, t, None))
        else:
            out.append((entry["round"], c, t, round(float(acc), 3)))
    return out


def run_case(model, key, expected_path):
    out = "/tmp/copper_quill_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run(
        [sys.executable, SOLVE, model, key, out],
        capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0 or not os.path.exists(out):
        return False
    try:
        with open(out) as f:
            got = json.load(f)
        with open(expected_path) as f:
            want = json.load(f)
        return norm(got) == norm(want)
    except Exception:
        return False


failures = []
if no_modify_broken:
    failures.append("visible inputs modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/score.py")
else:
    # --- visible case: EXECUTE score.py on the live supplied inputs ---
    if not (os.path.isfile("/app/model.json") and os.path.isfile("/app/key.json")):
        failures.append("visible inputs missing")
    elif not run_case("/app/model.json", "/app/key.json", "/tests/expected.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/report.json must match expected ---
    if os.path.isfile(REPORT):
        try:
            with open(REPORT) as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if norm(got) != norm(want):
                failures.append("report.json does not match visible expected")
        except Exception:
            failures.append("report.json unreadable")
    else:
        failures.append("missing /app/report.json")

    # --- hidden cases: genuinely distinct inputs with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            model = os.path.join(base, "model.json")
            key = os.path.join(base, "key.json")
            exp = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in (model, key, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(model, key, exp):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0