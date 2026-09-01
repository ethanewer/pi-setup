#!/bin/bash
# Verifier for rust-quill: checks the visible-case deliverables are present and
# correct, ENFORCES the no-modify rule on the supplied /app inputs, calls the
# module function directly, and EXECUTES the deliverable program
# (/app/emd_distance.py) on the visible case and on every hidden case in
# /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures in /app.
PRISTINE_PLAN_SHA="9d1f7973fd214e85445307e5681f186fbe5c867fa29581193e403099d3ca6bf7"
PRISTINE_COST_SHA="d3f91dcee273824e2f4f8f5be70470d46435abcbc02b0ea097c78ee27f8e2c24"

no_modify_broken=0
if [ ! -f /app/plan.json ]; then
    echo "no-modify: /app/plan.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/plan.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_PLAN_SHA" ]; then
        echo "no-modify: /app/plan.json was modified" >&2
        no_modify_broken=1
    fi
fi
if [ ! -f /app/cost.json ]; then
    echo "no-modify: /app/cost.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/cost.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_COST_SHA" ]; then
        echo "no-modify: /app/cost.json was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import importlib.util
import json, math, os, subprocess, sys, tempfile

SOLVE = "/app/emd_distance.py"
no_modify_broken = int(sys.argv[1])


def close(a, b):
    try:
        return math.isclose(float(a), float(b), rel_tol=1e-9, abs_tol=1e-12)
    except Exception:
        return False


def run_cli(plan_path, cost_path, expected):
    """Execute the deliverable CLI and compare against an expected distance."""
    out = "/tmp/rust_quill_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run(
        [sys.executable, SOLVE, "--plan", plan_path, "--cost", cost_path,
         "--out", out],
        capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0 or not os.path.exists(out):
        return False
    try:
        with open(out) as f:
            got = json.load(f)
        assert isinstance(got, dict) and set(got.keys()) == {"distance"}, got
        return close(got["distance"], expected["distance"])
    except Exception:
        return False


failures = []
if no_modify_broken:
    failures.append("visible inputs modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/emd_distance.py")
else:
    # --- module function must exist and be importable ---
    spec = importlib.util.spec_from_file_location("emd_distance", SOLVE)
    try:
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        has_fn = hasattr(mod, "sqrt_wasserstein") and callable(mod.sqrt_wasserstein)
    except Exception as exc:
        print("module import failed:", exc)
        has_fn = False
    if not has_fn:
        failures.append("module does not expose callable sqrt_wasserstein")

    # --- shape mismatch must raise ValueError / exit nonzero ---
    bad_plan = "/tmp/rust_quill_bad_plan.json"
    bad_cost = "/tmp/rust_quill_bad_cost.json"
    with open(bad_plan, "w") as f:
        json.dump([[1.0, 2.0], [3.0, 4.0]], f)
    with open(bad_cost, "w") as f:
        json.dump([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0], [7.0, 8.0, 9.0]], f)
    if has_fn:
        try:
            mod.sqrt_wasserstein([[1.0, 2.0]], [[1.0, 2.0, 3.0]])
            failures.append("sqrt_wasserstein must raise ValueError on shape mismatch")
        except ValueError:
            pass
        except Exception:
            failures.append("shape mismatch must raise ValueError")
    r = subprocess.run(
        [sys.executable, SOLVE, "--plan", bad_plan, "--cost", bad_cost,
         "--out", "/tmp/rust_quill_bad_out.json"],
        capture_output=True, text=True, timeout=120,
    )
    if r.returncode == 0:
        failures.append("CLI must exit nonzero on shape mismatch")

    # --- visible case ---
    if not (os.path.isfile("/app/plan.json") and os.path.isfile("/app/cost.json")):
        failures.append("visible inputs missing")
    else:
        with open("/tests/expected.json") as f:
            want = json.load(f)
        if not run_cli("/app/plan.json", "/app/cost.json", want):
            failures.append("visible case failed")
        if has_fn:
            with open("/app/plan.json") as f:
                P = json.load(f)
            with open("/app/cost.json") as f:
                C = json.load(f)
            if not close(mod.sqrt_wasserstein(P, C), want["distance"]):
                failures.append("module function disagrees on visible matrices")

    # --- visible-case deliverable: /app/distance.json must exist and match ---
    if os.path.isfile("/app/distance.json"):
        try:
            with open("/app/distance.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if not (isinstance(got, dict) and set(got.keys()) == {"distance"}
                    and close(got["distance"], want["distance"])):
                failures.append("distance.json does not match visible expected")
        except Exception:
            failures.append("distance.json unreadable")
    else:
        failures.append("missing /app/distance.json")

    # --- hidden cases ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            plan = os.path.join(base, "plan.json")
            cost = os.path.join(base, "cost.json")
            exp = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in (plan, cost, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            with open(exp) as f:
                expected = json.load(f)
            if not run_cli(plan, cost, expected):
                failures.append("hidden case '%s' failed" % c)
            if has_fn:
                with open(plan) as f:
                    P = json.load(f)
                with open(cost) as f:
                    C = json.load(f)
                if not close(mod.sqrt_wasserstein(P, C), expected["distance"]):
                    failures.append("hidden function case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
