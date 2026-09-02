#!/bin/bash
# Verifier for crimson-fjord: checks the visible-case deliverables are present
# and correct, ENFORCES the no-modify rule on the supplied /app input, and
# EXECUTES the deliverable program (/app/solve.py) on the visible case and on
# every hidden case in /tests/hidden. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixture in /app (the instruction
# tells the agent not to modify it; tampering defeats the visible-case check).
PRISTINE_SHA="41d2e518979e0187f14b3718889ce1bce5cb26f3d30e004ee0ee9beae42a3187"

no_modify_broken=0
if [ ! -f /app/pulse.jsonl ]; then
    echo "no-modify: /app/pulse.jsonl missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/pulse.jsonl | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_SHA" ]; then
        echo "no-modify: /app/pulse.jsonl was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/solve.py"
no_modify_broken = int(sys.argv[1])


def norm(obj):
    """Normalize a report, enforcing precision AND type contracts:
    tips/skipped/counts must be ints, amounts must be floats rounded to 2dp."""
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {"tips", "skipped", "tags"}, sorted(obj.keys())
    tips, skipped, tags = obj["tips"], obj["skipped"], obj["tags"]
    assert isinstance(tips, int) and not isinstance(tips, bool), tips
    assert isinstance(skipped, int) and not isinstance(skipped, bool), skipped
    assert isinstance(tags, dict), tags
    norm_tags = {}
    for k, v in tags.items():
        assert isinstance(v, dict) and set(v.keys()) == {"count", "amount"}, (k, v)
        c, a = v["count"], v["amount"]
        assert isinstance(c, int) and not isinstance(c, bool), (k, c)
        assert isinstance(a, float), (k, a, "amount must be a JSON float")
        norm_tags[k] = {"count": c, "amount": round(a, 2)}
    return (tips, skipped, norm_tags)


def run_case(inp, expected_path):
    out = "/tmp/crimson_fjord_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run(
        [sys.executable, SOLVE, inp, out],
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
    failures.append("visible input modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")
else:
    # --- visible case: EXECUTE solve.py on the live supplied input ---
    if not os.path.isfile("/app/pulse.jsonl"):
        failures.append("visible input missing")
    elif not run_case("/app/pulse.jsonl", "/tests/expected.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/answer.json must exist and match ---
    if os.path.isfile("/app/answer.json"):
        try:
            with open("/app/answer.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if norm(got) != norm(want):
                failures.append("answer.json does not match visible expected")
        except Exception:
            failures.append("answer.json unreadable")
    else:
        failures.append("missing /app/answer.json")

    # --- hidden cases: GENUINELY distinct inputs with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            inp = os.path.join(base, "input.jsonl")
            exp = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in (inp, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(inp, exp):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
