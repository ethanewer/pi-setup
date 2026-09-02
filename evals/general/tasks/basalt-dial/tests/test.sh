#!/bin/bash
# Verifier for basalt-dial: ENFORCES no-modify on the shipped engine and
# visible case, validates the delivered config, EXECUTES the engine with the
# agent's config on the visible case and every hidden case, and compares each
# final state to the reference model within the case tolerance. Writes REWARD
# (0/1) to /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_ENGINE_SHA="caef31ba8449dba5c01f42a88b65b77b84d680ca1927b3fc72747242fdb8f65f"
PRISTINE_CASE_SHA="b97ebf9822c0869f3397a6e7bf5792e87d7fe94342203a61dd7c707f5c0eabd8"

no_modify_broken=0
if [ ! -f /app/engine.py ]; then
    echo "no-modify: /app/engine.py missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/engine.py | awk '{print $1}')"
    [ "$actual" != "$PRISTINE_ENGINE_SHA" ] && { echo "no-modify: engine.py modified" >&2; no_modify_broken=1; }
fi
if [ ! -f /app/data/case_visible.json ]; then
    echo "no-modify: /app/data/case_visible.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/data/case_visible.json | awk '{print $1}')"
    [ "$actual" != "$PRISTINE_CASE_SHA" ] && { echo "no-modify: case_visible.json modified" >&2; no_modify_broken=1; }
fi

python3 - "$no_modify_broken" <<'PY'
import json, math, os, subprocess, sys

ENGINE = "/app/engine.py"
CONFIG = "/app/config/tuning.json"
REPORT = "/app/tuning_report.json"
no_modify_broken = int(sys.argv[1])


def run_engine(args):
    try:
        r = subprocess.run([sys.executable, ENGINE] + args,
                           capture_output=True, text=True, timeout=120)
        return r
    except Exception:
        return None


def load(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except Exception:
        return None


failures = []
if no_modify_broken:
    failures.append("shipped engine/case modified or missing (no-modify rule)")

if not os.path.isfile(CONFIG):
    failures.append("missing /app/config/tuning.json")
else:
    # --- config must be schema-valid: engine exits 0 on it ---
    probe = "/tmp/basalt_dial_probe.json"
    r = run_engine(["simulate", "/app/data/case_visible.json", CONFIG, probe])
    if r is None or r.returncode != 0 or not os.path.exists(probe):
        failures.append("config rejected by engine (invalid schema or run error)")

    if not failures:
        # --- hidden cases: randomized initial states within documented ranges ---
        hidden_dir = "/tests/hidden"
        cases = []
        if os.path.isdir(hidden_dir):
            for c in sorted(os.listdir(hidden_dir)):
                cj = os.path.join(hidden_dir, c, "case.json")
                if os.path.isfile(cj):
                    cases.append(cj)
        if not cases:
            cases = ["/app/data/case_visible.json"]
            failures.append("no hidden cases present")
        for case_path in ["/app/data/case_visible.json"] + cases:
            case = load(case_path)
            if not isinstance(case, dict):
                failures.append("case unreadable: %s" % case_path)
                continue
            tol = case.get("tol")
            budget = case.get("budget")
            sim_out = "/tmp/basalt_dial_sim.json"
            ref_out = "/tmp/basalt_dial_ref.json"
            if os.path.exists(sim_out):
                os.remove(sim_out)
            if os.path.exists(ref_out):
                os.remove(ref_out)
            r1 = run_engine(["simulate", case_path, CONFIG, sim_out])
            r2 = run_engine(["reference", case_path, ref_out])
            got = load(sim_out)
            want = load(ref_out)
            ok = (r1 is not None and r2 is not None and r1.returncode == 0
                  and r2.returncode == 0 and isinstance(got, dict)
                  and isinstance(want, dict))
            if ok:
                ok = (got.get("status") == "ok"
                      and isinstance(got.get("nfev"), int)
                      and got["nfev"] <= budget
                      and isinstance(got.get("final"), list)
                      and len(got["final"]) == 4
                      and all(isinstance(v, (int, float))
                              and math.isfinite(v) for v in got["final"])
                      and isinstance(want.get("final"), list))
            if ok:
                d = max(abs(a - b) for a, b in zip(got["final"], want["final"]))
                ok = d <= tol
            if not ok:
                failures.append("case %s failed" % case_path)
        if not failures:
            # --- deliverable 2: report must equal a fresh run of the config ---
            if not os.path.isfile(REPORT):
                failures.append("missing /app/tuning_report.json")
            else:
                fresh = "/tmp/basalt_dial_fresh.json"
                r = run_engine(["simulate", "/app/data/case_visible.json",
                                CONFIG, fresh])
                rep = load(REPORT)
                new = load(fresh)
                if r is None or r.returncode != 0 or rep is None or new is None:
                    failures.append("tuning_report.json re-run failed")
                elif rep != new:
                    failures.append("tuning_report.json does not match fresh run")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
