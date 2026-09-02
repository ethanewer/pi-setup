#!/bin/bash
# Verifier for harbor-loom: checks the deliverables are present and correct,
# ENFORCES the no-modify rule on the supplied /app fixtures, and EXECUTES the
# deliverable client (/app/seqfetch.py) on the visible case and on every hidden
# case in /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures in /app (the instruction
# tells the agent not to modify these; tampering defeats the visible check).
PRISTINE_SERVER_SHA="651d15542ace5dfeefeaac49c6d4d61b952df26d74ea6cb9abdb8f6550f566a0"
PRISTINE_DB_SHA="cede0141b5bd2b957c83bf9d8803aa85fad5a3bd45ac4b5d96d36ea6d5408883"
PRISTINE_REQ_SHA="952f3663878a0d5ee5df51dba5c11615b36ead8d9859e06b468e7328e10f99c6"

no_modify_broken=0
for pair in \
    "/app/api_server.py:$PRISTINE_SERVER_SHA" \
    "/app/data/db.json:$PRISTINE_DB_SHA" \
    "/app/data/requests.json:$PRISTINE_REQ_SHA"; do
    path="${pair%%:*}"
    want="${pair#*:}"
    if [ ! -f "$path" ]; then
        echo "no-modify: $path missing" >&2
        no_modify_broken=1
        continue
    fi
    actual="$(sha256sum "$path" | awk '{print $1}')"
    if [ "$actual" != "$want" ]; then
        echo "no-modify: $path was modified" >&2
        no_modify_broken=1
    fi
done

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

CLIENT = "/app/seqfetch.py"
no_modify_broken = int(sys.argv[1])
failures = []


def norm(obj):
    """Normalize a report so the comparison is exact but structure-checked."""
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {"sequences", "checksum_failures"}, obj.keys()
    sequences = obj["sequences"]
    failures = obj["checksum_failures"]
    assert isinstance(sequences, dict) and isinstance(failures, list)
    out = {}
    for key, seq in sequences.items():
        assert isinstance(seq, str), (key, seq)
        out[str(key)] = seq
    return out, sorted(str(f) for f in failures)


def run_case(data_dir, expected_path, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    try:
        r = subprocess.run(
            [sys.executable, CLIENT, data_dir, out_path],
            capture_output=True, text=True, timeout=120,
        )
    except subprocess.TimeoutExpired:
        return False
    if r.returncode != 0 or not os.path.exists(out_path):
        return False
    try:
        with open(out_path) as f:
            got = json.load(f)
        with open(expected_path) as f:
            want = json.load(f)
        return norm(got) == norm(want)
    except Exception:
        return False


if no_modify_broken:
    failures.append("visible fixtures modified or missing (no-modify rule)")

if not os.path.isfile(CLIENT):
    failures.append("missing /app/seqfetch.py")
else:
    # --- visible case: EXECUTE the client on the live supplied fixtures ---
    if not run_case("/app/data", "/tests/expected.json",
                    "/tmp/harbor_loom_visible.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/sequences_out.json must match ---
    if os.path.isfile("/app/sequences_out.json"):
        try:
            with open("/app/sequences_out.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if norm(got) != norm(want):
                failures.append("sequences_out.json does not match visible expected")
        except Exception:
            failures.append("sequences_out.json unreadable")
    else:
        failures.append("missing /app/sequences_out.json")

    # --- hidden cases: fresh databases + request lists with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            data = os.path.join(base, "data")
            exp = os.path.join(base, "expected.json")
            if not os.path.isdir(data) or not os.path.isfile(exp):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(data, exp, "/tmp/harbor_loom_hidden_out.json"):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
