#!/bin/bash
# Verifier for cinder-dial: checks the visible-case deliverables are present and
# correct, ENFORCES the no-modify rule on the supplied /app input, and EXECUTES
# the deliverable program (/app/rounds.py) on the visible case and on every
# hidden case in /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixture in /app (the instruction tells
# the agent not to modify it; tampering defeats the visible-case check).
PRISTINE_INPUT_SHA="ecbedc73846cb98cad19df6d8946007a3dbb8ad525619e471d4cd5f257058b60"

no_modify_broken=0
if [ ! -f /app/rounds.json ]; then
    echo "no-modify: /app/rounds.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/rounds.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_INPUT_SHA" ]; then
        echo "no-modify: /app/rounds.json was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/rounds.py"
no_modify_broken = int(sys.argv[1])


def norm(obj):
    """Independent re-normalization used to compare produced vs expected JSON."""
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {"overall", "rounds"}, obj.keys()
    overall = obj["overall"]
    assert set(overall.keys()) == {"correct", "total", "accuracy"}, overall
    rounds = obj["rounds"]
    norm_rounds = []
    for r in rounds:
        assert set(r.keys()) == {"round", "correct", "total", "accuracy"}, r
        acc = r["accuracy"]
        if acc is not None:
            acc = round(float(acc), 3)
        norm_rounds.append(
            (int(r["round"]), int(r["correct"]), int(r["total"]), acc)
        )
    norm_rounds.sort(key=lambda t: t[0])
    oacc = overall["accuracy"]
    if oacc is not None:
        oacc = round(float(oacc), 3)
    return (int(overall["correct"]), int(overall["total"]), oacc, norm_rounds)


def close(a, b):
    return abs(a - b) < 1e-9


def acc_eq(got, want):
    if want is None:
        return got is None
    return got is not None and close(got, want)


def check(obj, expected_path):
    try:
        with open(expected_path) as f:
            want = json.load(f)
    except Exception:
        return False
    try:
        got = norm(obj)
        wnt = norm(want)
    except Exception:
        return False
    if got[0] != wnt[0] or got[1] != wnt[1] or not acc_eq(got[2], wnt[2]):
        return False
    if len(got[3]) != len(wnt[3]):
        return False
    for g, w in zip(got[3], wnt[3]):
        if g[:3] != w[:3] or not acc_eq(g[3], w[3]):
            return False
    return True


def run_case(inp, expected_path):
    out = "/tmp/cinder_dial_verify_out.json"
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
    except Exception:
        return False
    return check(got, expected_path)


failures = []
if no_modify_broken:
    failures.append("visible input modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/rounds.py")
else:
    # --- visible case: EXECUTE rounds.py on the live supplied input ---
    if not os.path.isfile("/app/rounds.json"):
        failures.append("visible input missing")
    elif not run_case("/app/rounds.json", "/tests/expected.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/answer.json must match the expected ---
    if os.path.isfile("/app/answer.json"):
        try:
            with open("/app/answer.json") as f:
                got = json.load(f)
            if not check(got, "/tests/expected.json"):
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
            inp = os.path.join(base, "input.json")
            exp = os.path.join(base, "expected.json")
            if not (os.path.isfile(inp) and os.path.isfile(exp)):
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
