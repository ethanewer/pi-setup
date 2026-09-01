#!/bin/bash
# Verifier for cobalt-tide (executes-deliverable).
#
# ENFORCES the no-modify rule on the supplied /app fixtures, then EXECUTES the
# deliverable program /app/train_yield.py on the visible case and on every
# hidden case under /tests/hidden (two fresh feature/target fab runs of the
# same relationship family, plus a shape-mismatched pair and a missing-file
# probe). For every passing case it independently recomputes the Spearman rank
# correlation from the emitted per-seed test predictions against the
# ground-truth target and requires >= 0.92 on EVERY seed, plus full report
# structure. Writes REWARD (0/1) to /logs/verifier/reward.txt. Never crashes
# on malformed agent output.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures in /app (the instruction
# tells the agent not to modify these; tampering defeats the visible check).
PRISTINE_FEAT_SHA="c31af62dd20953984c7086a6f7a2f45a63d08a2abecc0848ae0b876abc81bb4f"
PRISTINE_TARG_SHA="723c00e979911703d375ef4c91b222286dab5ae1dda5cf96d307cfec8ba12642"

no_modify_broken=0
if [ ! -f /app/wafer_features.npy ] || [ ! -f /app/wafer_yield.npy ]; then
    echo "no-modify: /app fixtures missing" >&2
    no_modify_broken=1
else
    feat_sha="$(sha256sum /app/wafer_features.npy | awk '{print $1}')"
    targ_sha="$(sha256sum /app/wafer_yield.npy | awk '{print $1}')"
    if [ "$feat_sha" != "$PRISTINE_FEAT_SHA" ]; then
        echo "no-modify: /app/wafer_features.npy was modified" >&2
        no_modify_broken=1
    fi
    if [ "$targ_sha" != "$PRISTINE_TARG_SHA" ]; then
        echo "no-modify: /app/wafer_yield.npy was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

import numpy as np
from scipy.stats import spearmanr

PROG = "/app/train_yield.py"
REPORT = "/app/yield_report.json"
HID = "/tests/hidden"
N_SEEDS = 10
THRESHOLD = 0.92

no_modify_broken = int(sys.argv[1])
failures = []


def run_prog(feat, targ, out):
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, PROG, "--features", feat, "--target", targ,
             "--n_seeds", str(N_SEEDS), "--threshold", str(THRESHOLD),
             "--out", out],
            capture_output=True, text=True, timeout=600)
    except Exception as exc:
        return 1, str(exc)
    return r.returncode, (r.stderr or "")[-500:]


def check_report(rep, X, y, label):
    """Structural + gate checks, re-derived from the documented contract."""
    if not isinstance(rep, dict):
        return "%s: report is not a JSON object" % label
    want_keys = {"feature_columns", "n_rows", "n_seeds", "threshold",
                 "test_fraction", "all_pass", "min_spearman", "seeds"}
    if set(rep.keys()) != want_keys:
        return "%s: keys %s != %s" % (label, sorted(rep.keys()), sorted(want_keys))
    n_rows, d = X.shape
    if rep["feature_columns"] != d or rep["n_rows"] != n_rows:
        return "%s: feature_columns/n_rows disagree with the input matrix" % label
    if rep["n_seeds"] != N_SEEDS:
        return "%s: n_seeds %s != %s" % (label, rep["n_seeds"], N_SEEDS)
    if abs(float(rep["threshold"]) - THRESHOLD) > 1e-9:
        return "%s: threshold %s != %s" % (label, rep["threshold"], THRESHOLD)
    frac = float(rep["test_fraction"])
    if not (0.1 - 1e-9 <= frac <= 0.3 + 1e-9):
        return "%s: test_fraction %s outside [0.1, 0.3]" % (label, frac)
    seeds = rep["seeds"]
    if not isinstance(seeds, list) or len(seeds) != N_SEEDS:
        return "%s: seeds must be a list of %d entries" % (label, N_SEEDS)
    seen = set()
    id_sets = []
    for row in seeds:
        if not isinstance(row, dict):
            return "%s: seed entry not an object" % label
        need = {"seed", "n_train", "test_size", "spearman", "test_ids", "test_pred"}
        if set(row.keys()) != need:
            return "%s: seed entry keys %s != %s" % (label, sorted(row.keys()), sorted(need))
        s = row["seed"]
        if s in seen:
            return "%s: seed %s appears more than once" % (label, s)
        seen.add(s)
        ids = row["test_ids"]
        preds = row["test_pred"]
        if not (isinstance(ids, list) and isinstance(preds, list)):
            return "%s (seed %s): test_ids/test_pred not lists" % (label, s)
        if len(ids) != len(preds) or len(ids) != row["test_size"]:
            return "%s (seed %s): test_ids/test_pred length mismatch" % (label, s)
        if row["n_train"] + row["test_size"] != n_rows:
            return "%s (seed %s): n_train + test_size != n_rows" % (label, s)
        if not (0.1 - 1e-9 <= row["test_size"] / float(n_rows) <= 0.3 + 1e-9):
            return "%s (seed %s): holdout fraction %s outside [0.1,0.3]" % (
                label, s, row["test_size"] / float(n_rows))
        try:
            id_arr = np.asarray([int(i) for i in ids], dtype=int)
            pr_arr = np.asarray([float(v) for v in preds], dtype=float)
        except Exception:
            return "%s (seed %s): test_ids/test_pred not numeric" % (label, s)
        if id_arr.min() < 0 or id_arr.max() >= n_rows or len(set(id_arr.tolist())) != len(id_arr):
            return "%s (seed %s): test_ids not distinct in-range row indices" % (label, s)
        yt = y[id_arr]
        if not np.all(np.isfinite(pr_arr)):
            return "%s (seed %s): non-finite predictions" % (label, s)
        sp = float(spearmanr(yt, pr_arr).correlation)
        if not np.isfinite(sp):
            return "%s (seed %s): recomputed Spearman is not finite" % (label, s)
        if sp < THRESHOLD:
            return "%s (seed %s): recomputed held-out Spearman %.4f < %s" % (
                label, s, sp, THRESHOLD)
        rep_sp = float(row["spearman"])
        if abs(rep_sp - sp) > 0.01:
            return "%s (seed %s): reported Spearman %.4f disagrees with recomputed %.4f" % (
                label, s, rep_sp, sp)
        id_sets.append(frozenset(id_arr.tolist()))
    if seen != set(range(N_SEEDS)):
        return "%s: seeds present %s != 0..%d" % (label, sorted(seen), N_SEEDS - 1)
    if len(set(id_sets)) != N_SEEDS:
        return "%s: two seeds reused an identical holdout" % label
    if rep["all_pass"] is not True:
        return "%s: all_pass is not true" % label
    if float(rep["min_spearman"]) < THRESHOLD:
        return "%s: min_spearman %s < %s" % (label, rep["min_spearman"], THRESHOLD)
    return None


def expect_pass(feat, targ, label):
    if not os.path.isfile(PROG):
        failures.append("missing /app/train_yield.py")
        return
    rc, err = run_prog(feat, targ, "/tmp/ct_verify_out.json")
    if rc != 0 or not os.path.isfile("/tmp/ct_verify_out.json"):
        failures.append("%s: program exited rc=%s (%s)" % (label, rc, err.strip()[-200:]))
        return
    try:
        with open("/tmp/ct_verify_out.json") as fh:
            rep = json.load(fh)
        X = np.load(feat)
        y = np.load(targ)
        msg = check_report(rep, X, y, label)
        if msg:
            failures.append(msg)
    except Exception as exc:
        failures.append("%s: verification error: %r" % (label, exc))


def expect_fail(feat, targ, label):
    if not os.path.isfile(PROG):
        failures.append("missing /app/train_yield.py")
        return
    rc, _ = run_prog(feat, targ, "/tmp/ct_verify_out.json")
    if rc == 0:
        failures.append("%s: expected non-zero exit for invalid inputs" % label)


if no_modify_broken:
    failures.append("visible inputs missing (no-modify rule)")

if not failures:
    # visible case: execute the deliverable on the supplied fixtures
    expect_pass("/app/wafer_features.npy", "/app/wafer_yield.npy", "visible")
    # visible-case deliverable report must also clear the gate on its own
    if os.path.isfile(REPORT):
        try:
            with open(REPORT) as fh:
                rep = json.load(fh)
            X = np.load("/app/wafer_features.npy")
            y = np.load("/app/wafer_yield.npy")
            msg = check_report(rep, X, y, "visible-report")
            if msg:
                failures.append(msg)
        except Exception as exc:
            failures.append("visible-report unreadable: %r" % exc)
    else:
        failures.append("missing /app/yield_report.json")

    # hidden generalization cases: fresh fab runs, different n and d
    expect_pass(os.path.join(HID, "alpha", "features.npy"),
                os.path.join(HID, "alpha", "target.npy"), "hidden-alpha")
    expect_pass(os.path.join(HID, "beta", "features.npy"),
                os.path.join(HID, "beta", "target.npy"), "hidden-beta")

    # invalid-input probes: shape mismatch and missing file -> non-zero exit
    expect_fail(os.path.join(HID, "mismatch", "features.npy"),
                os.path.join(HID, "mismatch", "target.npy"), "hidden-mismatch")
    expect_fail(os.path.join(HID, "missing", "features.npy"),
                os.path.join(HID, "missing", "target.npy"), "hidden-missing")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
