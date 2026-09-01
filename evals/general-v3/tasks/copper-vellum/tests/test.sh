#!/bin/bash
# Verifier for copper-vellum (executes-deliverable).
#
#  * Checks /app/routine.py exists and the visible-case deliverable
#    /app/answer.json exists and matches an independent recomputation.
#  * ENFORCES the no-modify rule on the shipped /app fixtures.
#  * EXECUTES /app/routine.py on the visible input and on every hidden case
#    under /tests/hidden, comparing truth_id exactly and the v1..v5 chain
#    values numerically against the case's expected.json.
#
# Writes REWARD (0/1) to /logs/verifier/reward.txt. Never consults the oracle.
set -u

mkdir -p /logs/verifier

PRISTINE_INPUT_SHA="9694417c5644b13410dc11abe69fd0554712c506019186ec6dcd5613154477e2"

no_modify_broken=0
if [ ! -f /app/input.json ]; then
    echo "no-modify: /app/input.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/input.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_INPUT_SHA" ]; then
        echo "no-modify: /app/input.json was modified" >&2
        no_modify_broken=1
    fi
fi
if [ ! -f /app/routine.png ]; then
    echo "no-modify: /app/routine.png missing" >&2
    no_modify_broken=1
fi
export NO_MODIFY_BROKEN="$no_modify_broken"

python3 - <<'PY'
import json, os, subprocess, sys

failures = []
if os.environ.get("NO_MODIFY_BROKEN") == "1":
    failures.append("visible inputs modified or missing (no-modify rule)")

SOLVE = "/app/routine.py"


def photographed_run(a, b):
    # Independent recompute of the photographed routine (berthq, build 3).
    base = a * 17
    alt = b ^ 3
    if base > alt:
        base = base - alt
    else:
        base = base + 2 * alt
    return (base // 2) % 1009


def expected_for(a, b):
    v1 = a * 2
    v2 = b ^ 33
    v3 = v1 + v2
    v4 = v1 | v3
    samples = dict(v1=v1, v2=v2, v3=v3, v4=v4, v5=v4 >> 2)
    v4g = (v4 ^ 26) if v3 > 37 else (v4 + 37)
    trace = dict(v1=v1, v2=v2, v3=v3, v4=v4g, v5=v4g >> 2)
    return {"truth_id": photographed_run(a, b), "samples": samples, "trace": trace}


def norm(obj):
    assert isinstance(obj, dict), "answer is not a dict: %r" % (obj,)
    assert set(obj.keys()) == {"truth_id", "samples", "trace"}, sorted(obj.keys())
    out = {}
    ti = obj["truth_id"]
    assert isinstance(ti, (int, float)), ti
    out["truth_id"] = round(float(ti), 4)
    for part in ("samples", "trace"):
        d = obj[part]
        assert isinstance(d, dict), part
        assert set(d.keys()) == {"v1", "v2", "v3", "v4", "v5"}, sorted(d.keys())
        out[part] = {k: round(float(v), 4) for k, v in sorted(d.items())}
    return out


def load_norm(path, what):
    try:
        with open(path) as fh:
            return norm(json.load(fh))
    except Exception as exc:
        failures.append("%s unreadable/invalid: %s" % (what, exc))
        return None


def execute(inp_path):
    """Execute the deliverable on inp_path; return normalized answer or None."""
    out = "/tmp/copper_vellum_out.json"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run([sys.executable, SOLVE, inp_path, out],
                           capture_output=True, text=True, timeout=120)
    except Exception as exc:
        failures.append("exec failed on %s: %s" % (inp_path, exc))
        return None
    if r.returncode != 0 or not os.path.exists(out):
        failures.append("program failed on %s (rc=%s)" % (inp_path, r.returncode))
        return None
    return load_norm(out, "output for %s" % inp_path)


if not os.path.isfile(SOLVE):
    failures.append("missing deliverable /app/routine.py")
else:
    # --- visible case: recompute expected, EXECUTE deliverable, compare ---
    vis = None
    try:
        with open("/app/input.json") as fh:
            vis = json.load(fh)
        a, b = int(vis["a"]), int(vis["b"])
        want = norm(expected_for(a, b))
        got = execute("/app/input.json")
        if got is not None and got != want:
            failures.append("visible case mismatch: got %r want %r" % (got, want))
    except Exception as exc:
        failures.append("visible case failed: %s" % exc)

    # --- visible-case deliverable: /app/answer.json must match too ---
    if vis is not None:
        want = norm(expected_for(int(vis["a"]), int(vis["b"])))
        got = load_norm("/app/answer.json", "/app/answer.json")
        if got is not None and got != want:
            failures.append("/app/answer.json does not match visible expected")

    # --- hidden cases: EXECUTE the deliverable on each and compare ---
    hidden_dir = "/tests/hidden"
    cases = sorted(os.listdir(hidden_dir)) if os.path.isdir(hidden_dir) else []
    if not cases:
        failures.append("no hidden cases present")
    for c in cases:
        base = os.path.join(hidden_dir, c)
        inp = os.path.join(base, "input.json")
        exp = os.path.join(base, "expected.json")
        if not (os.path.isfile(inp) and os.path.isfile(exp)):
            failures.append("hidden case '%s' malformed" % c)
            continue
        got = execute(inp)
        want = load_norm(exp, "expected for '%s'" % c)
        if got is not None and want is not None and got != want:
            failures.append("hidden case '%s' mismatch: got %r want %r"
                            % (c, got, want))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

rc=$?
if [ $rc -eq 0 ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
