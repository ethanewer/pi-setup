#!/bin/bash
# Verifier for topaz-marsh: enforces the no-modify rule on the visible
# instance, checks /app/answer.json, and EXECUTES /app/wmaxsat.py on every
# hidden instance. Writes 0/1 to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE="e58f6a5a6efcdaa13024e521bd49e81cba0162b4ac9e7aeaa4abb3b79b1dce81"
if [ ! -f /app/instances/visible.wcnf ]; then
    echo "no-modify: /app/instances/visible.wcnf missing" >&2
    broken=1
else
    actual="$(sha256sum /app/instances/visible.wcnf | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE" ]; then
        echo "no-modify: visible.wcnf was modified" >&2
        broken=1
    else
        broken=0
    fi
fi

python3 - "$broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/wmaxsat.py"
broken = int(sys.argv[1])
failures = []

if broken:
    failures.append("visible instance modified or missing")


def norm(obj):
    if not isinstance(obj, dict):
        raise ValueError("not a dict")
    status = obj.get("status")
    if status == "HARD_UNSAT":
        if set(obj.keys()) != {"status"}:
            raise ValueError("extra keys with HARD_UNSAT")
        return ("HARD_UNSAT", None)
    if status == "OPTIMAL":
        if set(obj.keys()) != {"status", "objective"}:
            raise ValueError("wrong keys with OPTIMAL")
        objv = obj["objective"]
        if isinstance(objv, bool) or not isinstance(objv, int):
            raise ValueError("objective must be an integer")
        return ("OPTIMAL", objv)
    raise ValueError("bad status %r" % (status,))


def run_case(instance, expected_path, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, instance, out_path],
            capture_output=True, text=True, timeout=150,
        )
    except Exception as e:
        return "execution error: %r" % (e,)
    if r.returncode != 0 or not os.path.exists(out_path):
        return "exit %d without output" % r.returncode
    try:
        got = norm(json.load(open(out_path)))
        want = norm(json.load(open(expected_path)))
    except Exception as e:
        return "unreadable output: %r" % (e,)
    if got != want:
        return "mismatch: got %r want %r" % (got, want)
    return None


if not os.path.isfile(SOLVE):
    failures.append("missing /app/wmaxsat.py")
else:
    if not broken:
        err = run_case("/app/instances/visible.wcnf", "/tests/expected.json",
                       "/tmp/topaz_marsh_visible_out.json")
        if err:
            failures.append("visible case: " + err)

    # the shipped answer.json must match the visible expected
    if not os.path.isfile("/app/answer.json"):
        failures.append("missing /app/answer.json")
    else:
        try:
            if norm(json.load(open("/app/answer.json"))) != \
               norm(json.load(open("/tests/expected.json"))):
                failures.append("/app/answer.json does not match visible expected")
        except Exception as e:
            failures.append("answer.json unreadable: %r" % (e,))

    hidden = "/tests/hidden"
    cases = sorted(os.listdir(hidden)) if os.path.isdir(hidden) else []
    if not cases:
        failures.append("no hidden cases present")
    for case in cases:
        base = os.path.join(hidden, case)
        inst, exp = os.path.join(base, "instance.wcnf"), os.path.join(base, "expected.json")
        if not (os.path.isfile(inst) and os.path.isfile(exp)):
            failures.append("hidden '%s' malformed fixture" % case)
            continue
        err = run_case(inst, exp, "/tmp/topaz_marsh_out_%s.json" % case)
        if err:
            failures.append("hidden '%s': %s" % (case, err))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
