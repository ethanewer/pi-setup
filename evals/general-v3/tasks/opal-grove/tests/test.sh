#!/bin/bash
# Verifier for opal-grove: validates the agent's prototxt solver/network
# definitions, ENFORCES the no-modify rule on the shipped fixtures, EXECUTES
# the frozen cafelite trainer with the agent's definitions on the visible and
# hidden datasets, and cross-checks /app/run_report.json.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_CAFELITE_SHA="c64e437a8ff2f7bf82b1fca457d46707f1fadc28c3a73a0bf2be3c52825cdde6"
PRISTINE_TRAIN_SHA="093adb717aefdc4c4993204460a8c731dc05512912dabe0d22d9afadb297d7b8"
PRISTINE_TEST_SHA="ad3da098c705ffe74405ba1a6ef340a63816db3ad62e7b1fc5ceb750d87e6c80"

no_modify_broken=0
check_sha() {
    local path="$1" want="$2" label="$3"
    if [ ! -f "$path" ]; then
        echo "no-modify: $label missing" >&2
        no_modify_broken=1
        return
    fi
    local actual
    actual="$(sha256sum "$path" | awk '{print $1}')"
    if [ "$actual" != "$want" ]; then
        echo "no-modify: $label was modified" >&2
        no_modify_broken=1
    fi
}
check_sha /app/cafelite.py "$PRISTINE_CAFELITE_SHA" "/app/cafelite.py"
check_sha /app/data/train.csv "$PRISTINE_TRAIN_SHA" "/app/data/train.csv"
check_sha /app/data/test.csv "$PRISTINE_TEST_SHA" "/app/data/test.csv"

python3 - "$no_modify_broken" <<'PY'
import json
import os
import subprocess
import sys

sys.path.insert(0, "/app")
import cafelite  # noqa: E402  (frozen trainer: parser + validator)

CAFE = "/app/cafelite.py"
SOLVER = "/app/solver.prototxt"
TRAIN_NET = "/app/train_net.prototxt"
TEST_NET = "/app/test_net.prototxt"
AGENT_REPORT = "/app/run_report.json"
VISIBLE_MIN_ACC = 0.85
no_modify_broken = int(sys.argv[1])


def run_trainer(train_csv, test_csv, report_out):
    if os.path.exists(report_out):
        os.remove(report_out)
    return subprocess.run(
        [sys.executable, CAFE, SOLVER,
         "--train", train_csv, "--test", test_csv, "--report", report_out],
        capture_output=True, text=True, timeout=240, cwd="/app",
    )


def load_report(path):
    try:
        with open(path) as fh:
            return json.load(fh), None
    except Exception as exc:
        return None, repr(exc)


def reports_match(a, b, tol=1e-4):
    if not isinstance(a, dict) or not isinstance(b, dict):
        return False
    if set(a.keys()) != set(b.keys()):
        return False
    for k in a:
        va, vb = a[k], b[k]
        if isinstance(va, (int, float)) and not isinstance(va, bool):
            if not isinstance(vb, (int, float)) or abs(float(va) - float(vb)) > tol:
                return False
        elif va != vb:
            return False
    return True


failures = []
if no_modify_broken:
    failures.append("shipped fixtures modified or missing (no-modify rule)")

# --- structural validation of the agent's definition files ---
solver = None
try:
    solver = cafelite.parse_solver(SOLVER)
except Exception as exc:
    failures.append("solver.prototxt invalid: %r" % (exc,))
try:
    train_net = cafelite.parse_net(TRAIN_NET)
except Exception as exc:
    failures.append("train_net.prototxt invalid: %r" % (exc,))
    train_net = None
try:
    test_net = cafelite.parse_net(TEST_NET)
except Exception as exc:
    failures.append("test_net.prototxt invalid: %r" % (exc,))
    test_net = None

if solver is not None:
    if str(solver.get("solver_mode", "")).upper() != "CPU":
        failures.append("solver_mode is not CPU")
    mi = solver.get("max_iter")
    if not isinstance(mi, int) or not (1 <= mi <= cafelite.MAX_ITER_CAP):
        failures.append("max_iter %r outside the [1, %d] cap" % (mi, cafelite.MAX_ITER_CAP))

if train_net and test_net and train_net["input_dim"] != test_net["input_dim"]:
    failures.append("train/test input_dim mismatch")

# --- EXECUTE the trainer with the agent's definitions: visible case ---
if solver is not None and train_net is not None and test_net is not None:
    r = run_trainer("/app/data/train.csv", "/app/data/test.csv", "/tmp/opal_vis.json")
    if r.returncode != 0:
        failures.append("cafelite run failed on visible data: %s" % r.stderr[-300:])
    else:
        fresh, err = load_report("/tmp/opal_vis.json")
        if err or not isinstance(fresh, dict):
            failures.append("visible run report unreadable: %s" % err)
        else:
            if fresh.get("final_test_accuracy", 0.0) < VISIBLE_MIN_ACC:
                failures.append(
                    "visible test accuracy %s < %s"
                    % (fresh.get("final_test_accuracy"), VISIBLE_MIN_ACC)
                )
            if os.path.isfile(AGENT_REPORT):
                agent, aerr = load_report(AGENT_REPORT)
                if aerr or not reports_match(agent, fresh):
                    failures.append(
                        "/app/run_report.json does not match a fresh trainer run"
                    )
            else:
                failures.append("missing /app/run_report.json")

    # --- hidden cases: same definitions, different datasets ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        for case in sorted(os.listdir(hidden_dir)):
            base = os.path.join(hidden_dir, case)
            tcsv, scsv, exp_path = (
                os.path.join(base, "train.csv"),
                os.path.join(base, "test.csv"),
                os.path.join(base, "expected.json"),
            )
            if not all(os.path.isfile(p) for p in (tcsv, scsv, exp_path)):
                failures.append("hidden '%s' malformed" % case)
                continue
            try:
                want = json.load(open(exp_path))
            except Exception:
                failures.append("hidden '%s' expected.json unreadable" % case)
                continue
            min_acc = want.get("min_test_accuracy", 0.0)
            out = "/tmp/opal_%s.json" % case
            r = run_trainer(tcsv, scsv, out)
            if r.returncode != 0:
                failures.append("hidden '%s': cafelite failed: %s" % (case, r.stderr[-300:]))
                continue
            rep, err = load_report(out)
            if err or not isinstance(rep, dict):
                failures.append("hidden '%s': report unreadable" % case)
                continue
            if rep.get("final_test_accuracy", 0.0) < min_acc:
                failures.append(
                    "hidden '%s': test accuracy %s < %s"
                    % (case, rep.get("final_test_accuracy"), min_acc)
                )
            if solver is not None and rep.get("max_iter") != solver.get("max_iter"):
                failures.append("hidden '%s': iteration count mismatch" % case)
    else:
        failures.append("no hidden cases present")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
