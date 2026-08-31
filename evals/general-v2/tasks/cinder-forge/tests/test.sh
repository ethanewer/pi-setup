#!/bin/bash
# Verifier for cinder-forge: checks the visible-case deliverables are present
# and correct, ENFORCES the no-modify rule on the supplied /app fixture, and
# EXECUTES the deliverable scanner (/app/scan.py) on the visible case and on
# every hidden case in /tests/hidden. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixture (the instruction tells the
# agent not to modify it; tampering defeats the visible-case check).
PRISTINE_SRC_SHA="02d8e4fe9957044a13ea5862939e912af38831f506a0e1385bea13374671bd19"

no_modify_broken=0
if [ ! -f /app/billing_api.py ]; then
    echo "no-modify: /app/billing_api.py missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/billing_api.py | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_SRC_SHA" ]; then
        echo "no-modify: /app/billing_api.py was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SCANNER = "/app/scan.py"
no_modify_broken = int(sys.argv[1])


def norm(obj):
    """Normalize a findings report into a comparable canonical structure."""
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {"findings"}, obj.keys()
    items = []
    for f in obj["findings"]:
        assert isinstance(f, dict), f
        assert set(f.keys()) == {"line", "rule", "cwe"}, f.keys()
        items.append((int(f["line"]), str(f["rule"]), str(f["cwe"])))
    items.sort()
    return items


def run_case(source, expected_path, tag):
    out = "/tmp/cinder_forge_verify_%s.json" % abs(hash(tag))
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, SCANNER, source, out],
            capture_output=True, text=True, timeout=120,
        )
    except subprocess.TimeoutExpired:
        return "timeout"
    if r.returncode != 0 or not os.path.exists(out):
        return "exit=%d" % r.returncode
    try:
        with open(out) as f:
            got = json.load(f)
        with open(expected_path) as f:
            want = json.load(f)
        if norm(got) != norm(want):
            return "mismatch"
        return None
    except Exception as exc:
        return "unreadable: %s" % exc
    finally:
        if os.path.exists(out):
            os.remove(out)


failures = []
if no_modify_broken:
    failures.append("visible input modified or missing (no-modify rule)")

if not os.path.isfile(SCANNER):
    failures.append("missing /app/scan.py")
else:
    # --- visible case: EXECUTE scan.py on the live supplied fixture ---
    if not os.path.isfile("/app/billing_api.py"):
        failures.append("visible fixture missing")
    else:
        err = run_case("/app/billing_api.py", "/tests/expected.json", "visible")
        if err:
            failures.append("visible case failed: %s" % err)

    # --- visible-case deliverable: /app/findings.json must exist and match ---
    if os.path.isfile("/app/findings.json"):
        try:
            with open("/app/findings.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if norm(got) != norm(want):
                failures.append("findings.json does not match visible expected")
        except Exception:
            failures.append("findings.json unreadable")
    else:
        failures.append("missing /app/findings.json")

    # --- hidden cases: distinct source files with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            src = os.path.join(base, "source.py")
            exp = os.path.join(base, "expected.json")
            if not (os.path.isfile(src) and os.path.isfile(exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            err = run_case(src, exp, c)
            if err:
                failures.append("hidden case '%s' failed: %s" % (c, err))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
