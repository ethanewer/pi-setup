#!/bin/bash
# Verifier for marlin-rig: checks the visible deliverables, ENFORCES the
# no-modify rule on the shipped /app/data fixture, and EXECUTES /app/fit.py on
# the visible scenario and on every hidden scenario in /tests/hidden, comparing
# the full result JSON to the reference. Writes REWARD (0/1) to
# /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the shipped visible scenario files.
declare -A PRISTINE=(
  [scenario.json]="6176fbaf8ffc5f19df4e098e6368f915d1428f0e2f4b48c3926248ae4e21b143"
  [view_a.txt]="ebfe97e39a22c4d0e6e14b00fdd356a5e99a48047c977ff005b00b8b1bd3abd7"
  [view_b.txt]="825233769caf36a3d21c34126b1e1bc7cd576a8b6d9029071477ce04a54166c1"
  [keypoints_a.json]="7f556a1568895c90e74e618dc0a96b08c387d3515f04f28cbc7128f9c123e2c6"
  [keypoints_b.json]="79878f855ce2754bce1e0a65c6520c2aa700c03723fb03cb16c607642e2de368"
)

no_modify_broken=0
for fname in scenario.json view_a.txt view_b.txt keypoints_a.json keypoints_b.json; do
  f="/app/data/scenario/$fname"
  if [ ! -f "$f" ]; then
    echo "no-modify: $f missing" >&2
    no_modify_broken=1
    continue
  fi
  actual="$(sha256sum "$f" | awk '{print $1}')"
  if [ "$actual" != "${PRISTINE[$fname]}" ]; then
    echo "no-modify: $f was modified" >&2
    no_modify_broken=1
  fi
done

python3 - "$no_modify_broken" <<'PY'
import json, math, os, subprocess, sys

SOLVE = "/app/fit.py"
no_modify_broken = int(sys.argv[1])

TOP_KEYS = {"scenario", "tau", "n_keypoints_a", "n_keypoints_b",
            "n_skipped_a", "n_skipped_b", "n_matches", "matches", "status",
            "params", "inliers", "n_inliers", "rms_inlier", "residuals"}
PARAM_KEYS = {"scale", "theta", "tx", "ty"}


def close(x, y):
    return isinstance(x, (int, float)) and isinstance(y, (int, float)) \
        and math.isclose(float(x), float(y), rel_tol=1e-9, abs_tol=1e-5)


def eq_norm(got, want):
    """Structural comparison with float tolerance; raises on structure bugs."""
    if not isinstance(got, dict) or not isinstance(want, dict):
        raise ValueError("top level not a dict")
    if set(got.keys()) != TOP_KEYS or set(want.keys()) != TOP_KEYS:
        raise ValueError("bad top-level keys")
    for k in ("scenario", "status"):
        if got[k] != want[k]:
            return False
    for k in ("tau", "n_keypoints_a", "n_keypoints_b", "n_skipped_a",
              "n_skipped_b", "n_matches", "n_inliers"):
        if isinstance(want[k], int) and isinstance(got[k], int):
            if got[k] != want[k]:
                return False
        elif not close(got[k], want[k]):
            return False
    if got["matches"] != want["matches"]:
        return False
    if got["inliers"] != want["inliers"]:
        return False
    # params
    if want["params"] is None:
        if got["params"] is not None:
            return False
    else:
        if not isinstance(got["params"], dict) or set(got["params"].keys()) != PARAM_KEYS:
            raise ValueError("bad params")
        for k in PARAM_KEYS:
            if not close(got["params"][k], want["params"][k]):
                return False
    # rms (scalar) / residuals (list); both null on degenerate
    if want["rms_inlier"] is None:
        if got["rms_inlier"] is not None:
            return False
    elif not close(got["rms_inlier"], want["rms_inlier"]):
        return False
    if want["residuals"] is None:
        if got["residuals"] is not None:
            return False
    else:
        g, w = got["residuals"], want["residuals"]
        if not isinstance(g, list) or len(g) != len(w):
            return False
        for gv, wv in zip(g, w):
            if not close(gv, wv):
                return False
    return True


def run_case(scen_dir, expected_path):
    out = "/tmp/marlin_rig_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, scen_dir, out],
            capture_output=True, text=True, timeout=120,
        )
    except Exception:
        return False
    if r.returncode != 0 or not os.path.exists(out):
        return False
    try:
        with open(out) as f:
            got = json.load(f)
        with open(expected_path) as f:
            want = json.load(f)
        return eq_norm(got, want)
    except Exception:
        return False


failures = []
if no_modify_broken:
    failures.append("shipped scenario modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/fit.py")
else:
    # --- visible case: EXECUTE fit.py on the shipped scenario ---
    if not os.path.isdir("/app/data/scenario") or not os.path.isfile("/tests/expected.json"):
        failures.append("visible scenario files missing")
    elif not run_case("/app/data/scenario", "/tests/expected.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/fit_result.json must match expected ---
    if os.path.isfile("/app/fit_result.json"):
        try:
            with open("/app/fit_result.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if not eq_norm(got, want):
                failures.append("fit_result.json does not match visible expected")
        except Exception:
            failures.append("fit_result.json unreadable")
    else:
        failures.append("missing /app/fit_result.json")

    # --- hidden scenarios: distinct rasters/keypoints/tolerances ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(d for d in os.listdir(hidden_dir)
                       if os.path.isdir(os.path.join(hidden_dir, d)))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            exp = os.path.join(base, "expected.json")
            if not (os.path.isfile(exp)
                    and os.path.isfile(os.path.join(base, "scenario.json"))
                    and os.path.isfile(os.path.join(base, "view_a.txt"))
                    and os.path.isfile(os.path.join(base, "view_b.txt"))
                    and os.path.isfile(os.path.join(base, "keypoints_a.json"))
                    and os.path.isfile(os.path.join(base, "keypoints_b.json"))):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(base, exp):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
