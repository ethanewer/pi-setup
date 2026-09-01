#!/bin/bash
# Verifier for kestrel-loop: checks the visible deliverables, ENFORCES the
# no-modify rule on the shipped /app fixtures, and EXECUTES /app/spec_loop.py
# on the visible case and on every hidden case in /tests/hidden, comparing the
# full output JSON to the reference. Writes REWARD (0/1) to
# /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the shipped visible fixtures (instruction forbids modifying them).
PRISTINE_MODEL_SHA="fab7e40bc340b20cfb21ea9dee106164f6cd052c6d7fb6595869f8abce330a43"
PRISTINE_CASE_SHA="7473380dd080404f3e73caac08436b3e1d2129a55019cfba1f80bcb7d0e74830"

no_modify_broken=0
if [ ! -f /app/data/model.json ]; then
    echo "no-modify: /app/data/model.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/data/model.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_MODEL_SHA" ]; then
        echo "no-modify: /app/data/model.json was modified" >&2
        no_modify_broken=1
    fi
fi
if [ ! -f /app/spec_case.txt ]; then
    echo "no-modify: /app/spec_case.txt missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/spec_case.txt | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_CASE_SHA" ]; then
        echo "no-modify: /app/spec_case.txt was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/spec_loop.py"
no_modify_broken = int(sys.argv[1])

REQ_KEYS = {"vocab_size", "prefix", "target", "draft_len", "result",
            "n_drafted", "n_accepted", "n_corrected", "blocks"}


def norm(obj):
    """Canonicalize a loop-result JSON; raise on any structural problem."""
    assert isinstance(obj, dict), type(obj)
    assert set(obj.keys()) == REQ_KEYS, sorted(obj.keys())
    assert isinstance(obj["vocab_size"], int)
    out = {
        "vocab_size": int(obj["vocab_size"]),
        "prefix": [int(x) for x in obj["prefix"]],
        "target": [int(x) for x in obj["target"]],
        "draft_len": int(obj["draft_len"]),
        "result": [int(x) for x in obj["result"]],
        "n_drafted": int(obj["n_drafted"]),
        "n_accepted": int(obj["n_accepted"]),
        "n_corrected": int(obj["n_corrected"]),
        "blocks": [],
    }
    for b in obj["blocks"]:
        assert isinstance(b, dict), b
        assert set(b.keys()) == {"start", "draft", "accepted", "rejected"}, sorted(b.keys())
        out["blocks"].append({
            "start": int(b["start"]),
            "draft": [int(x) for x in b["draft"]],
            "accepted": int(b["accepted"]),
            "rejected": bool(b["rejected"]),
        })
    return out


def parse_case(path):
    """Parse a key=value case file -> dict; model path resolved by caller."""
    kv = {}
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or "=" not in line:
                continue
            k, _, v = line.partition("=")
            kv[k.strip()] = v.strip()
    return kv


def run_case(model_path, prefix, target, draft, expected_path):
    out = "/tmp/kestrel_loop_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, "--model", model_path,
             "--prefix", prefix, "--target", target,
             "--draft", str(draft), "--out", out],
            capture_output=True, text=True, timeout=120,
        )
    except Exception:
        return False
    if r.returncode != 0 or not os.path.exists(out):
        return False
    try:
        with open(out) as f:
            got = norm(json.load(f))
        with open(expected_path) as f:
            want = norm(json.load(f))
    except Exception:
        return False
    if got != want:
        return False
    # invariant: the loop must absorb prefix + target exactly
    if got["result"] != got["prefix"] + got["target"]:
        return False
    if got["n_corrected"] != len(got["target"]) - got["n_accepted"]:
        return False
    return True


failures = []
if no_modify_broken:
    failures.append("shipped inputs modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/spec_loop.py")
else:
    # --- visible case: EXECUTE spec_loop.py on the shipped inputs ---
    vis_case = "/app/spec_case.txt"
    if not os.path.isfile(vis_case) or not os.path.isfile("/tests/expected.json"):
        failures.append("visible case files missing")
    else:
        try:
            kv = parse_case(vis_case)
            model = kv["model"]
            if not os.path.isabs(model) and not os.path.exists(model):
                model = os.path.join(os.path.dirname(vis_case), model)
            ok = run_case(model, kv.get("prefix", ""), kv.get("target", ""),
                          kv.get("draft", "1"), "/tests/expected.json")
        except Exception:
            ok = False
        if not ok:
            failures.append("visible case failed")

    # --- visible-case deliverable: /app/spec_result.json must match expected ---
    if os.path.isfile("/app/spec_result.json"):
        try:
            with open("/app/spec_result.json") as f:
                got = norm(json.load(f))
            with open("/tests/expected.json") as f:
                want = norm(json.load(f))
            if got != want:
                failures.append("spec_result.json does not match visible expected")
        except Exception:
            failures.append("spec_result.json unreadable")
    else:
        failures.append("missing /app/spec_result.json")

    # --- hidden cases: distinct models/prefixes/targets/K with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(d for d in os.listdir(hidden_dir)
                       if os.path.isdir(os.path.join(hidden_dir, d)))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            case_f = os.path.join(base, "spec_case.txt")
            exp = os.path.join(base, "expected.json")
            if not (os.path.isfile(case_f) and os.path.isfile(exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            try:
                kv = parse_case(case_f)
                model = kv["model"]
                if not os.path.isabs(model) and not os.path.exists(model):
                    model = os.path.join(base, model)
                ok = run_case(model, kv.get("prefix", ""), kv.get("target", ""),
                              kv.get("draft", "1"), exp)
            except Exception:
                ok = False
            if not ok:
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
