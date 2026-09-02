#!/bin/bash
# Verifier for moor-latch: checks the visible deliverables, ENFORCES the
# no-modify rule on the supplied /app fixtures, and EXECUTES the deliverable
# client (/app/struct_client.py) on the visible db and on every hidden case in
# /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures in /app (the instruction
# tells the agent not to modify these; tampering defeats the visible check).
PRISTINE_SERVER_SHA="2ec0e28d43c6dda807c37315d9ec1a58b85de31f2a505f47c137741165d01d4e"
PRISTINE_ENTRIES_SHA="63690ac9707dfc60ee6b8abf822e09039ba7b0c2daff2194245da043a92f1ab8"
PRISTINE_SPEC_SHA="20dd883e7c7062ae47c69c2b95db8be040a4cc5250cd551ce13caf135d4663b2"

no_modify_broken=0
for pair in "/app/structure_server.py:$PRISTINE_SERVER_SHA" \
            "/app/db/entries.json:$PRISTINE_ENTRIES_SHA" \
            "/app/db/spec.json:$PRISTINE_SPEC_SHA"; do
    path="${pair%%:*}"
    want="${pair#*:}"
    if [ ! -f "$path" ]; then
        echo "no-modify: $path missing" >&2
        no_modify_broken=1
    else
        actual="$(sha256sum "$path" | awk '{print $1}')"
        if [ "$actual" != "$want" ]; then
            echo "no-modify: $path was modified" >&2
            no_modify_broken=1
        fi
    fi
done

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

CLIENT = "/app/struct_client.py"
no_modify_broken = int(sys.argv[1])


def norm(obj):
    """Normalize a report: exact keys, exact sequences, exact totals."""
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {"entries", "total_chains", "total_residues"}, obj
    entries = obj["entries"]
    assert isinstance(entries, dict), entries
    norm_entries = {}
    for eid, chains in entries.items():
        assert isinstance(eid, str) and isinstance(chains, dict), (eid, chains)
        for cid, seq in chains.items():
            assert isinstance(cid, str) and isinstance(seq, str) and seq, (cid, seq)
        norm_entries[eid] = dict(chains)
    tc = obj["total_chains"]
    tr = obj["total_residues"]
    assert isinstance(tc, int) and not isinstance(tc, bool), tc
    assert isinstance(tr, int) and not isinstance(tr, bool), tr
    return (norm_entries, tc, tr)


def run_case(data_dir, expected_path, out):
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, CLIENT, data_dir, out],
            capture_output=True, text=True, timeout=120,
        )
    except subprocess.TimeoutExpired:
        return False
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
    failures.append("supplied /app fixtures modified or missing (no-modify rule)")

if not os.path.isfile(CLIENT):
    failures.append("missing /app/struct_client.py")
else:
    # --- visible case: EXECUTE the client on the live supplied fixtures ---
    if not os.path.isfile("/app/db/entries.json") or not os.path.isfile("/app/db/spec.json"):
        failures.append("visible db fixtures missing")
    elif not run_case("/app/db", "/tests/expected.json", "/tmp/ml_verify_visible.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/struct_report.json must match ---
    if os.path.isfile("/app/struct_report.json"):
        try:
            with open("/app/struct_report.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if norm(got) != norm(want):
                failures.append("struct_report.json does not match visible expected")
        except Exception:
            failures.append("struct_report.json unreadable")
    else:
        failures.append("missing /app/struct_report.json")

    # --- hidden cases: fresh archives + specs with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            db = os.path.join(base, "db")
            exp = os.path.join(base, "expected.json")
            if not os.path.isfile(exp) or not os.path.isfile(os.path.join(db, "entries.json")) \
                    or not os.path.isfile(os.path.join(db, "spec.json")):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(db, exp, "/tmp/ml_verify_%s.json" % c):
                failures.append("hidden case '%s' failed" % c)
    else:
        failures.append("hidden case directory missing")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
