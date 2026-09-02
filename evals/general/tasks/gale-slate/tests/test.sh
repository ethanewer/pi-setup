#!/bin/bash
# Verifier for gale-slate: checks the visible deliverables are present and
# correct, ENFORCES the no-modify rule on the supplied /app fixture, and
# EXECUTES the deliverable program (/app/solve.py) on the visible fixture and
# on every hidden case in /tests/hidden. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixture (the instruction tells the
# agent not to modify it; tampering defeats the visible-case check).
PRISTINE_SRC_SHA="0c6cc0ed17bfdeab4bf7431149f39fb8905e5665888febcede3e2ca180cd8c81"

no_modify_broken=0
if [ ! -f /app/report_service.py ]; then
    echo "no-modify: /app/report_service.py missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/report_service.py | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_SRC_SHA" ]; then
        echo "no-modify: /app/report_service.py was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/solve.py"
no_modify_broken = int(sys.argv[1])


def norm(path):
    """Load a findings report and normalize it for comparison."""
    with open(path) as fh:
        obj = json.load(fh)
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {"findings"}, sorted(obj.keys())
    findings = obj["findings"]
    assert isinstance(findings, list), findings
    out = []
    for f in findings:
        assert isinstance(f, dict), f
        assert set(f.keys()) == {"component", "cwe"}, sorted(f.keys())
        assert isinstance(f["component"], str) and isinstance(f["cwe"], str), f
        out.append((f["component"], f["cwe"]))
    return sorted(out)


def run_case(src, expected_path):
    out = "/tmp/gale_slate_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run(
        [sys.executable, SOLVE, src, out],
        capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0 or not os.path.exists(out):
        return False
    try:
        return norm(out) == norm(expected_path)
    except Exception:
        return False


failures = []
if no_modify_broken:
    failures.append("visible fixture modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")
else:
    # --- visible case: EXECUTE solve.py on the live supplied fixture ---
    if not os.path.isfile("/app/report_service.py"):
        failures.append("visible fixture missing")
    elif not run_case("/app/report_service.py", "/tests/expected.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/answer.json must exist and match ---
    if os.path.isfile("/app/answer.json"):
        try:
            if norm("/app/answer.json") != norm("/tests/expected.json"):
                failures.append("answer.json does not match visible expected")
        except Exception:
            failures.append("answer.json unreadable")
    else:
        failures.append("missing /app/answer.json")

    # --- hidden cases: GENUINELY distinct sources with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            src = os.path.join(base, "module.py")
            exp = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in (src, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(src, exp):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
