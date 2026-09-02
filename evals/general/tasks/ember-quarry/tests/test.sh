#!/bin/bash
# Verifier for ember-quarry: EXECUTES the deliverable /app/mil.py on the visible
# fixture and on every hidden station under /tests/hidden, comparing against an
# independent in-container reference that follows the task spec. Also checks the
# visible deliverable /app/report.json. Writes 0/1 to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
python3 - <<'PYEOF' >&2
import json, os, subprocess, sys
import numpy as np
import torch

SOLVE = "/app/mil.py"
TOL = 1e-4
failures = []


def log(*a):
    print("[verifier]", *a)


def reference(cfg, X):
    """Independent spec-faithful reference (does NOT import the agent module)."""
    torch.manual_seed(cfg["seed"])
    enc = torch.nn.Linear(cfg["in_dim"], cfg["hidden"])
    gate = torch.nn.Linear(cfg["hidden"], 1)
    clf = torch.nn.Linear(cfg["hidden"], cfg["num_classes"])
    x = torch.from_numpy(np.asarray(X, dtype=np.float32))
    T = x.shape[0]
    emb = torch.relu(enc(x))
    if T == 0:
        w = torch.zeros(0, 1)
        logits = torch.zeros(cfg["num_classes"])
    else:
        w = torch.softmax(gate(emb), dim=0)
        logits = clf((emb * w).sum(dim=0))
    return {
        "logits": [float(v) for v in logits],
        "attention": [float(v) for v in w.reshape(-1)],
        "instance_count": int(T),
        "pred_class": int(torch.argmax(logits).item()),
    }


def close(got, want):
    if not isinstance(got, dict):
        return False
    if set(got.keys()) != {"logits", "attention", "instance_count", "pred_class"}:
        return False
    if not (isinstance(got["instance_count"], int)
            and isinstance(got["pred_class"], int)):
        return False
    for key in ("logits", "attention"):
        if not isinstance(got[key], list):
            return False
        if len(got[key]) != len(want[key]):
            return False
        try:
            g = [float(v) for v in got[key]]
        except (TypeError, ValueError):
            return False
        for a, b in zip(g, want[key]):
            if abs(a - b) > TOL or a != a:  # NaN guard
                return False
    return got["instance_count"] == want["instance_count"] and \
        got["pred_class"] == want["pred_class"]


def run_cli(cfg_path, bag_path):
    out = "/tmp/ember_quarry_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run(
        [sys.executable, SOLVE, "--config", cfg_path, "--bag", bag_path,
         "--out", out],
        capture_output=True, text=True, timeout=180,
    )
    if r.returncode != 0:
        log("CLI failed:", r.stderr[-500:])
        return None
    if not os.path.exists(out):
        return None
    try:
        with open(out) as fh:
            return json.load(fh)
    except Exception as e:
        log("unreadable output:", repr(e))
        return None


def check_case(name, cfg_path, bag_path, expect_path):
    with open(cfg_path) as fh:
        cfg = json.load(fh)
    with np.load(bag_path) as data:
        X = np.asarray(data["X"], dtype=np.float32)
    want = reference(cfg, X)
    got = run_cli(cfg_path, bag_path)
    if got is None:
        failures.append("case '%s': CLI did not produce output" % name)
        return
    if not close(got, want):
        failures.append("case '%s': output mismatch vs reference" % name)
        return
    # structural invariants from the baked expectation file
    try:
        with open(expect_path) as fh:
            exp = json.load(fh)
    except Exception as e:
        failures.append("case '%s': unreadable expect.json (%r)" % (name, e))
        return
    T = got["instance_count"]
    if T != exp.get("instance_count"):
        failures.append("case '%s': wrong instance_count" % name)
        return
    if len(got["attention"]) != T or len(got["logits"]) != exp.get("logits_len"):
        failures.append("case '%s': wrong list lengths" % name)
        return
    if exp.get("attention_sums_to_one"):
        s = sum(float(v) for v in got["attention"])
        if abs(s - 1.0) > 1e-4:
            failures.append("case '%s': attention sums to %r" % (name, s))
            return
    if exp.get("pred_class_is_argmax") and \
            got["pred_class"] != int(np.argmax(np.asarray(got["logits"]))):
        failures.append("case '%s': pred_class != argmax" % name)


if not os.path.isfile(SOLVE):
    failures.append("missing /app/mil.py")
else:
    # visible case: execute the deliverable on the shipped fixture
    check_case("visible", "/app/config.json", "/app/input/bag.npz",
               "/tests/visible_expect.json")
    # visible deliverable /app/report.json must match the same reference
    if os.path.isfile("/app/report.json"):
        try:
            with open("/app/config.json") as fh:
                cfg = json.load(fh)
            with np.load("/app/input/bag.npz") as data:
                X = np.asarray(data["X"], dtype=np.float32)
            with open("/app/report.json") as fh:
                got = json.load(fh)
            if not close(got, reference(cfg, X)):
                failures.append("visible deliverable report.json mismatch")
        except Exception as e:
            failures.append("report.json unreadable: %r" % e)
    else:
        failures.append("missing /app/report.json")

    hidden = "/tests/hidden"
    cases = sorted(os.listdir(hidden)) if os.path.isdir(hidden) else []
    if not cases:
        failures.append("no hidden cases present")
    for name in cases:
        base = os.path.join(hidden, name)
        paths = [os.path.join(base, f) for f in ("config.json", "bag.npz",
                                                 "expect.json")]
        if not all(os.path.isfile(p) for p in paths):
            failures.append("hidden case '%s' malformed" % name)
            continue
        check_case(name, *paths)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PYEOF
rc=$?
if [ $rc -eq 0 ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
