#!/bin/bash
# Verifier for cobalt-wharf: checks the visible-case deliverables are present
# and correct, ENFORCES the no-modify rule on the supplied /app inputs, and
# EXECUTES the deliverable program (/app/score_report.py) on the visible case
# and on every hidden case in /tests/hidden. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures in /app (the instruction
# tells the agent not to modify these; tampering defeats the visible check).
PRISTINE_PRED_SHA="2ab167b913303864768c78fe10ea4164629a0f566403ab86bf8a91fa04a180d6"
PRISTINE_KEY_SHA="ac827d5f48976e37a480b9acce8b1309e06175fde0cc15498d49a57cf39ec561"

no_modify_broken=0
if [ ! -f /app/predictions.json ]; then
    echo "no-modify: /app/predictions.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/predictions.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_PRED_SHA" ]; then
        echo "no-modify: /app/predictions.json was modified" >&2
        no_modify_broken=1
    fi
fi
if [ ! -f /app/answer_key.json ]; then
    echo "no-modify: /app/answer_key.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/answer_key.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_KEY_SHA" ]; then
        echo "no-modify: /app/answer_key.json was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, math, os, subprocess, sys

SOLVE = "/app/score_report.py"
no_modify_broken = int(sys.argv[1])


def is_valid(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def norm_accuracy(acc):
    if acc is None:
        return None
    assert is_valid(acc), acc
    return round(float(acc), 6)


def norm(obj):
    """Normalize a report so we can compare it by content."""
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {"rounds", "totals"}, obj.keys()
    rounds = obj["rounds"]
    totals = obj["totals"]
    assert isinstance(rounds, dict), rounds
    nr = {}
    for r, entry in rounds.items():
        assert isinstance(entry, dict), entry
        assert set(entry.keys()) == {"correct", "total", "accuracy"}, entry
        c = int(entry["correct"])
        t = int(entry["total"])
        acc = norm_accuracy(entry["accuracy"])
        if acc is None:
            assert t == 0, ("null accuracy requires total==0", entry)
        nr[str(r)] = (c, t, acc)
    assert set(totals.keys()) == {"correct", "total", "accuracy"}, totals
    nt = (int(totals["correct"]), int(totals["total"]),
          norm_accuracy(totals["accuracy"]))
    return (nr, nt)


def close(a, b):
    if a is None or b is None:
        return a is b
    return math.isclose(a, b, rel_tol=0.0, abs_tol=1e-9)


def reports_equal(got, want):
    g, w = norm(got), norm(want)
    gr, wr = g[0], w[0]
    if set(gr) != set(wr):
        return False
    for r in gr:
        gc, gt, ga = gr[r]
        wc, wt, wa = wr[r]
        if gc != wc or gt != wt or not close(ga, wa):
            return False
    gc, gt, ga = g[1]
    wc, wt, wa = w[1]
    return gc == wc and gt == wt and close(ga, wa)


def run_case(pred, key, expected_path):
    out = "/tmp/cobalt_wharf_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run(
        [sys.executable, SOLVE, pred, key, out],
        capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0 or not os.path.exists(out):
        return False
    try:
        with open(out) as f:
            got = json.load(f)
        with open(expected_path) as f:
            want = json.load(f)
        return reports_equal(got, want)
    except Exception:
        return False


failures = []
if no_modify_broken:
    failures.append("visible inputs modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/score_report.py")
else:
    # --- visible case: EXECUTE score_report.py on the live supplied inputs ---
    if not (os.path.isfile("/app/predictions.json")
            and os.path.isfile("/app/answer_key.json")):
        failures.append("visible inputs missing")
    elif not run_case("/app/predictions.json", "/app/answer_key.json",
                      "/tests/expected.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/report.json must exist and match ---
    if os.path.isfile("/app/report.json"):
        try:
            with open("/app/report.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if not reports_equal(got, want):
                failures.append("report.json does not match visible expected")
        except Exception:
            failures.append("report.json unreadable")
    else:
        failures.append("missing /app/report.json")

    # --- hidden cases: GENUINELY distinct inputs with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            pred = os.path.join(base, "predictions.json")
            key = os.path.join(base, "answer_key.json")
            exp = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in (pred, key, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(pred, key, exp):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
