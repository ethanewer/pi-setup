#!/bin/bash
# Verifier for basalt-fjord: checks the visible-case deliverables are present
# and correct, ENFORCES the no-modify rule on the supplied /app input, EXECUTES
# the deliverable CLI (/app/emd.py) on the visible case and every hidden case
# in /tests/hidden, and imports /app/emd.distance directly. Writes REWARD (0/1)
# to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixture in /app (the instruction
# tells the agent not to modify it; tampering defeats the visible check).
PRISTINE_SHIPMENT_SHA="6998d75c975367f34469c7cc9d7c2b242ed24ba19e7091eda55f8b8e661ff150"

no_modify_broken=0
if [ ! -f /app/shipment.json ]; then
    echo "no-modify: /app/shipment.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/shipment.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_SHIPMENT_SHA" ]; then
        echo "no-modify: /app/shipment.json was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, math, os, subprocess, sys

MODULE = "/app/emd.py"
OUTJSON = "/app/distance.json"
no_modify_broken = int(sys.argv[1])

failures = []
if no_modify_broken:
    failures.append("visible input modified or missing (no-modify rule)")

if not os.path.isfile(MODULE):
    failures.append("missing /app/emd.py")
    print("verify failures:", failures)
    sys.exit(1)

def run_cli(inp, out):
    """Run the deliverable CLI; return (returncode, parsed_output_or_None)."""
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run(
        [sys.executable, MODULE, inp, out],
        capture_output=True, text=True, timeout=120,
    )
    parsed = None
    if r.returncode == 0 and os.path.exists(out):
        try:
            with open(out) as f:
                parsed = json.load(f)
        except Exception:
            parsed = None
    return r.returncode, parsed


def ref_distance(P, C):
    """Independent reference: sqrt of the non-negative-clamped dot product."""
    rows = len(P)
    cols = len(P[0])
    s = 0.0
    for i in range(rows):
        for j in range(len(P[i])):
            s += float(P[i][j]) * float(C[i][j])
    return math.sqrt(max(0.0, s))


def check_distance_value(d, want, tol=1e-6):
    if isinstance(d, bool) or not isinstance(d, (int, float)):
        return False
    if math.isnan(float(d)) or math.isinf(float(d)):
        return False
    return abs(float(d) - float(want)) <= tol * max(1.0, abs(float(want)))


# --- module-level checks (import the deliverable directly) ---
try:
    sys.path.insert(0, "/app")
    import emd  # noqa: E402

    pos = emd.distance([[0.3, 0.2], [0.2, 0.3]], [[1.0, 4.0], [4.0, 1.0]])
    if not abs(float(pos) - math.sqrt(2.2)) <= 1e-9:
        failures.append("module distance wrong on positive case: %r" % (pos,))
    if float(emd.distance([[0.0, 0.0], [0.0, 0.0]], [[5.0, -1.0], [0.0, 2.0]])) != 0.0:
        failures.append("module distance must return 0.0 for an all-zero plan")
    if float(emd.distance([[1.0, 1.0, 1.0]], [[-0.5, -0.5, -0.5]])) != 0.0:
        failures.append("module distance must clamp a negative dot product to 0.0")
    try:
        emd.distance([[1.0, 2.0]], [[1.0, 2.0, 3.0]])
        failures.append("module distance must raise ValueError on shape mismatch")
    except ValueError:
        pass
    except Exception as exc:
        failures.append("module distance raised %r, expected ValueError" % (exc,))
except Exception as exc:
    failures.append("importing /app/emd.py failed: %r" % (exc,))

# --- visible case: EXECUTE the CLI on the live supplied input ---
if not os.path.isfile("/app/shipment.json"):
    failures.append("visible input missing")
else:
    code, parsed = run_cli("/app/shipment.json", "/tmp/basalt_fjord_verify_out.json")
    try:
        with open("/tests/expected.json") as f:
            want = json.load(f)
    except Exception:
        want = None
        failures.append("verifier expected.json unreadable")
    if code != 0 or not isinstance(parsed, dict) or "distance" not in parsed:
        failures.append("visible CLI run failed (exit=%d)" % code)
    elif want is not None and not check_distance_value(parsed["distance"], want["distance"]):
        failures.append("visible case distance mismatch")

# --- visible-case deliverable: /app/distance.json must exist and match ---
if os.path.isfile(OUTJSON):
    try:
        with open(OUTJSON) as f:
            got = json.load(f)
        with open("/tests/expected.json") as f:
            want = json.load(f)
        if not (isinstance(got, dict) and "distance" in got
                and check_distance_value(got["distance"], want["distance"])):
            failures.append("distance.json does not match visible expected")
    except Exception:
        failures.append("distance.json unreadable")
else:
    failures.append("missing /app/distance.json")

# --- hidden cases: genuinely distinct inputs with their own expecteds ---
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
        try:
            with open(exp) as f:
                want = json.load(f)
        except Exception:
            failures.append("hidden '%s' expected unreadable" % c)
            continue
        code, parsed = run_cli(inp, "/tmp/basalt_fjord_verify_out.json")
        if "exit_code" in want:
            if code != want["exit_code"]:
                failures.append(
                    "hidden '%s' expected exit %d, got %d" % (c, want["exit_code"], code)
                )
            continue
        if code != 0 or not isinstance(parsed, dict) or "distance" not in parsed:
            failures.append("hidden '%s' CLI run failed (exit=%d)" % (c, code))
            continue
        if not check_distance_value(parsed["distance"], want["distance"]):
            failures.append("hidden '%s' distance mismatch" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0