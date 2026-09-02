#!/bin/bash
# Verifier for cinder-reef: checks the visible deliverables, ENFORCES the
# no-modify rule on the supplied /app fixtures, and EXECUTES the deliverable
# client (/app/fret_client.py) on the visible db and on every hidden case in
# /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures in /app (the instruction
# tells the agent not to modify these; tampering defeats the visible check).
PRISTINE_SERVER_SHA="9f35b85b9dcdbe1b98a96e1b469d5375e32e55b28ffdd7bbf155b18560526224"
PRISTINE_API_SHA="ceca61fc40d4349dfd4ff28c7872ab9ca9ee2ad0123d08f2cbb052cb2f0a3e4d"
PRISTINE_SPEC_SHA="8ff081ae46725e6bc972d901279e45b7cd0ad92114772a81512daaaeb64d829b"

no_modify_broken=0
for pair in "/app/spectra_server.py:$PRISTINE_SERVER_SHA" \
            "/app/db/api.json:$PRISTINE_API_SHA" \
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

CLIENT = "/app/fret_client.py"
no_modify_broken = int(sys.argv[1])


def norm(obj):
    """Normalize a report: exact keys, int wavelengths, exact ids."""
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {"donor", "acceptor", "gap_nm"}, obj
    for role in ("donor", "acceptor"):
        rec = obj[role]
        assert isinstance(rec, dict), rec
        assert set(rec.keys()) == {"id", "excitation_nm", "emission_nm"}, rec
        assert isinstance(rec["id"], str) and rec["id"], rec
        for k in ("excitation_nm", "emission_nm"):
            v = rec[k]
            assert isinstance(v, int) and not isinstance(v, bool), (k, v)
    gap = obj["gap_nm"]
    assert isinstance(gap, int) and not isinstance(gap, bool), gap
    return (
        obj["donor"]["id"], obj["donor"]["excitation_nm"], obj["donor"]["emission_nm"],
        obj["acceptor"]["id"], obj["acceptor"]["excitation_nm"], obj["acceptor"]["emission_nm"],
        gap,
    )


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
    failures.append("missing /app/fret_client.py")
else:
    # --- visible case: EXECUTE the client on the live supplied fixtures ---
    if not os.path.isfile("/app/db/api.json") or not os.path.isfile("/app/db/spec.json"):
        failures.append("visible db fixtures missing")
    elif not run_case("/app/db", "/tests/expected.json", "/tmp/cr_verify_visible.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/fret_report.json must match ---
    if os.path.isfile("/app/fret_report.json"):
        try:
            with open("/app/fret_report.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if norm(got) != norm(want):
                failures.append("fret_report.json does not match visible expected")
        except Exception:
            failures.append("fret_report.json unreadable")
    else:
        failures.append("missing /app/fret_report.json")

    # --- hidden cases: fresh databases + specs with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            db = os.path.join(base, "db")
            exp = os.path.join(base, "expected.json")
            if not os.path.isfile(exp) or not os.path.isfile(os.path.join(db, "api.json")) \
                    or not os.path.isfile(os.path.join(db, "spec.json")):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(db, exp, "/tmp/cr_verify_%s.json" % c):
                failures.append("hidden case '%s' failed" % c)
    else:
        failures.append("hidden case directory missing")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
