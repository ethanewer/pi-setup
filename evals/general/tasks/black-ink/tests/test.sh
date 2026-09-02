#!/bin/bash
# Verifier for black-ink: checks the visible-case deliverables are present and
# correct, ENFORCES the no-modify rule on the supplied /app inputs, and EXECUTES
# the deliverable program (/app/solve.py) on the visible case and on every hidden
# case in /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures in /app (the instruction tells
# the agent not to modify these; tampering defeats the visible-case check).
PRISTINE_LOG_SHA="86d6dfc5158092f16ea85c06f06311285b7a07595260f0ce5ba30103f382d36b"
PRISTINE_QUERY_SHA="ebbaea0f9c28866b0cb80912407af4da8c38256309b365a2eb7444a5139ae0cf"

no_modify_broken=0
if [ ! -f /app/operations.log ]; then
    echo "no-modify: /app/operations.log missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/operations.log | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_LOG_SHA" ]; then
        echo "no-modify: /app/operations.log was modified" >&2
        no_modify_broken=1
    fi
fi
if [ ! -f /app/query.txt ]; then
    echo "no-modify: /app/query.txt missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/query.txt | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_QUERY_SHA" ]; then
        echo "no-modify: /app/query.txt was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/solve.py"
no_modify_broken = int(sys.argv[1])


def norm(obj):
    """Normalize an answer so we can compare floats (rounded) and dicts by content."""
    assert isinstance(obj, dict), obj
    keys = set(obj.keys())
    assert keys == {"average_ms", "counts", "malformed"}, keys
    counts = obj["counts"]
    avg = obj["average_ms"]
    malformed = obj["malformed"]
    assert isinstance(malformed, int), malformed
    assert set(counts.keys()) == set(avg.keys()), (counts, avg)
    c = {k: int(v) for k, v in sorted(counts.items())}
    a = {k: round(float(v), 4) for k, v in sorted(avg.items())}
    return (malformed, c, a)


def run_case(log, query, expected_path):
    out = "/tmp/black_ink_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run(
        [sys.executable, SOLVE, log, query, out],
        capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0 or not os.path.exists(out):
        return False
    try:
        with open(out) as f:
            got = json.load(f)
        with open(expected_path) as f:
            want = json.load(f)
        return norm(got) == norm(want)
    except Exception:
        return False


failures = []
if no_modify_broken:
    failures.append("visible inputs modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")
else:
    # --- visible case: EXECUTE solve.py on the live supplied inputs ---
    if not (os.path.isfile("/app/operations.log") and os.path.isfile("/app/query.txt")):
        failures.append("visible inputs missing")
    elif not run_case("/app/operations.log", "/app/query.txt", "/tests/expected.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/answer.json must exist and match ---
    # expected for the visible inputs.
    if os.path.isfile("/app/answer.json"):
        try:
            with open("/app/answer.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if norm(got) != norm(want):
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
            log = os.path.join(base, "log.txt")
            query = os.path.join(base, "query.txt")
            exp = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in (log, query, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(log, query, exp):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0