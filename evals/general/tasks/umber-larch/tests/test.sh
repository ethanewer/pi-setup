#!/bin/bash
# Verifier for umber-larch: checks the visible deliverables, ENFORCES the
# no-modify rule on the shipped study, and EXECUTES the deliverable program
# (/app/estimate.py) on the visible study and on every hidden study under
# /tests/hidden, comparing each estimate to that study's true ATE within the
# documented tolerance. Writes 0/1 to /logs/verifier/reward.txt. Never crashes
# on malformed/missing agent output.
set -u

mkdir -p /logs/verifier
reward=0

no_modify_broken=0
for f in obs.csv dag.json; do
    if [ ! -f "/app/$f" ]; then
        echo "no-modify: /app/$f missing" >&2
        no_modify_broken=1
    fi
done
if [ "$no_modify_broken" = "0" ]; then
    for f in obs.csv dag.json; do
        want="$(cat "/tests/expected_visible/$f.sha" 2>/dev/null)"
        got="$(sha256sum "/app/$f" | awk '{print $1}')"
        if [ "$got" != "$want" ]; then
            echo "no-modify: /app/$f was modified" >&2
            no_modify_broken=1
        fi
    done
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, re, subprocess, sys

EST = "/app/estimate.py"
no_modify_broken = int(sys.argv[1])
failures = []

if no_modify_broken:
    failures.append("shipped study modified or missing (no-modify rule)")

NUM_RE = re.compile(r"^[+-]?\d+\.\d{6}$")


def run_est(obs, dag, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    try:
        return subprocess.run([sys.executable, EST, obs, dag, out_path],
                              capture_output=True, text=True, timeout=240)
    except Exception as e:
        print("run error:", e)
        return None


def parse_estimate(path):
    """Returns float, or (None, reason)."""
    try:
        with open(path) as fh:
            content = fh.read().strip()
    except Exception as e:
        return None, "unreadable output (%s)" % e
    lines = [l.strip() for l in content.splitlines() if l.strip()]
    if len(lines) != 1:
        return None, "expected exactly one non-empty line, got %d" % len(lines)
    if not NUM_RE.match(lines[0]):
        return None, "not a 6-decimal number: %r" % lines[0]
    try:
        return float(lines[0]), None
    except ValueError:
        return None, "unparseable number"


def check_study(obs, dag, exp_path, out_path, label):
    try:
        with open(exp_path) as fh:
            exp = json.load(fh)
        true_ate = float(exp["true_ate"])
        tol = float(exp.get("tol", 0.06))
    except Exception as e:
        return "bad expected file (%s)" % e
    r = run_est(obs, dag, out_path)
    if r is None or r.returncode != 0:
        return "run failed (rc=%s)" % (getattr(r, "returncode", None),)
    val, err = parse_estimate(out_path)
    if err:
        return err
    if abs(val - true_ate) > tol:
        return "estimate %.6f not within %.3f of truth %.6f" % (val, tol, true_ate)
    return None


if not os.path.isfile(EST):
    failures.append("missing /app/estimate.py")
else:
    # ---- visible study: execute the deliverable -----------------------------
    err = check_study("/app/obs.csv", "/app/dag.json", "/tests/expected.json",
                      "/tmp/ul_vis.txt", "visible")
    if err:
        failures.append("visible: " + err)
    # ---- visible answer.txt deliverable --------------------------------------
    if os.path.isfile("/app/answer.txt"):
        val, perr = parse_estimate("/app/answer.txt")
        if perr:
            failures.append("answer.txt: " + perr)
        else:
            try:
                with open("/tests/expected.json") as fh:
                    true_ate = float(json.load(fh)["true_ate"])
                if abs(val - true_ate) > 0.06:
                    failures.append("answer.txt: %.6f not within tolerance of %.6f"
                                    % (val, true_ate))
            except Exception as e:
                failures.append("answer.txt: bad expected (%s)" % e)
    else:
        failures.append("missing /app/answer.txt")

    # ---- hidden studies --------------------------------------------------------
    hidden = "/tests/hidden"
    cases = sorted(d for d in os.listdir(hidden)
                   if os.path.isdir(os.path.join(hidden, d))) if os.path.isdir(hidden) else []
    if not cases:
        failures.append("no hidden cases present")
    for c in cases:
        base = os.path.join(hidden, c)
        if not all(os.path.isfile(os.path.join(base, f))
                   for f in ("obs.csv", "dag.json", "expected.json")):
            failures.append("hidden '%s' malformed" % c)
            continue
        err = check_study(os.path.join(base, "obs.csv"),
                          os.path.join(base, "dag.json"),
                          os.path.join(base, "expected.json"),
                          "/tmp/ul_h_%s.txt" % c, "hidden/" + c)
        if err:
            failures.append("hidden '%s': %s" % (c, err))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
