#!/bin/bash
# Verifier for quill-anchor: checks the visible-case deliverables, ENFORCES the
# no-modify rule on the supplied /app inputs, EXECUTES the deliverable CLI
# (/app/movecost.py) on the visible case and every hidden case in /tests/hidden,
# and probes the module function route_distance directly (ValueError on shape
# mismatch, never-nan clamping). Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures in /app.
PRISTINE_PLAN_SHA="2d9de1cad936e071e81a28b0be5fce56f4379fa0c8fc31c28944c81878a8ba80"
PRISTINE_COST_SHA="5f3b6f3d2af1a27fc3310e745412f8bde45e3417cc6fa25725ad073be740d40a"

no_modify_broken=0
for f in /app/plan.csv /app/cost.csv; do
    if [ ! -f "$f" ]; then
        echo "no-modify: $f missing" >&2
        no_modify_broken=1
    fi
done
if [ "$no_modify_broken" -eq 0 ]; then
    a="$(sha256sum /app/plan.csv | awk '{print $1}')"
    b="$(sha256sum /app/cost.csv | awk '{print $1}')"
    [ "$a" != "$PRISTINE_PLAN_SHA" ] && { echo "no-modify: /app/plan.csv modified" >&2; no_modify_broken=1; }
    [ "$b" != "$PRISTINE_COST_SHA" ] && { echo "no-modify: /app/cost.csv modified" >&2; no_modify_broken=1; }
fi

python3 - "$no_modify_broken" <<'PY'
import importlib.util, json, math, os, subprocess, sys, tempfile

SOLVE = "/app/movecost.py"
no_modify_broken = int(sys.argv[1])
failures = []


def rooted(plan, cost):
    s = sum(p * c for pr, cr in zip(plan, cost) for p, c in zip(pr, cr))
    return math.sqrt(max(0.0, s))


def load_module():
    spec = importlib.util.spec_from_file_location("movecost", SOLVE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def read_csv(path):
    rows = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            cells = [t.strip() for t in line.split(",")] if "," in line else line.split()
            rows.append([float(t) for t in cells if t != ""])
    return rows


def run_cli(plan_csv, cost_csv):
    out = tempfile.mktemp(suffix=".json")
    r = subprocess.run(
        [sys.executable, SOLVE, plan_csv, cost_csv, out],
        capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0:
        return None, r
    try:
        with open(out) as f:
            data = json.load(f)
    except Exception:
        return None, r
    return data, r


def close(a, b):
    return abs(a - b) <= 1e-9 * max(1.0, abs(b))


def check_cli(plan_csv, cost_csv, expected_path):
    try:
        with open(expected_path) as f:
            want = json.load(f)
        wd = float(want["distance"])
    except Exception:
        return False
    data, _r = run_cli(plan_csv, cost_csv)
    if not isinstance(data, dict) or set(data.keys()) != {"distance"}:
        return False
    try:
        d = float(data["distance"])
    except Exception:
        return False
    if math.isnan(d) or d < 0:
        return False
    return close(d, wd)


if no_modify_broken:
    failures.append("visible inputs modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/movecost.py")
else:
    # --- module-level probes on the deliverable itself ---
    try:
        mod = load_module()
    except Exception as exc:
        mod = None
        failures.append("movecost.py not importable: %r" % (exc,))

    if mod is not None:
        if not hasattr(mod, "route_distance"):
            failures.append("missing route_distance function")
        else:
            # shape mismatch raises ValueError (including transposed shape)
            for plan, cost in (
                ([[1.0, 2.0], [3.0, 4.0]], [[1.0, 2.0]]),
                ([[1.0, 2.0]], [[1.0], [2.0]]),          # same cells, transposed
                ([[1.0, 2.0], [3.0]], [[1.0, 2.0], [3.0, 4.0]]),  # ragged
                ([[1.0]], []),                            # empty cost
            ):
                try:
                    mod.route_distance(plan, cost)
                    failures.append("route_distance(%r, %r) did not raise ValueError" % (plan, cost))
                except ValueError:
                    pass
                except Exception as exc:
                    failures.append("route_distance raised %r instead of ValueError" % (exc,))
            # clamping: negative dot and all-zero plan return exactly 0.0 float
            if mod.route_distance([[1.0]], [[-4.0]]) != 0.0:
                failures.append("negative dot product not clamped to 0.0")
            if mod.route_distance([[0.0, 0.0]], [[1.0, 2.0]]) != 0.0:
                failures.append("all-zero plan does not return 0.0")
            if not isinstance(mod.route_distance([[4]], [[4]]), float):
                failures.append("route_distance must return a Python float")

    # --- visible case: EXECUTE the CLI on the live supplied inputs ---
    if not (os.path.isfile("/app/plan.csv") and os.path.isfile("/app/cost.csv")):
        failures.append("visible inputs missing")
    elif not check_cli("/app/plan.csv", "/app/cost.csv", "/tests/expected.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/answer.json must match ---
    if os.path.isfile("/app/answer.json"):
        try:
            with open("/app/answer.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if not (isinstance(got, dict) and set(got) == {"distance"}
                    and close(float(got["distance"]), float(want["distance"]))):
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
            plan_csv = os.path.join(base, "plan.csv")
            cost_csv = os.path.join(base, "cost.csv")
            exp = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in (plan_csv, cost_csv, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not check_cli(plan_csv, cost_csv, exp):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
