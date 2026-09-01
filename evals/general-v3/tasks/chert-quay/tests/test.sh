#!/bin/bash
# Verifier for chert-quay: enforces the no-modify rule on /app/corrupt.db,
# checks the visible-case deliverables, and EXECUTES /app/solve.py on the
# visible case and on every hidden case in /tests/hidden. Writes 0/1 to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_DB_SHA="$(sha256sum /app/corrupt.db 2>/dev/null | awk '{print $1}')"

no_modify_broken=0
if [ ! -f /app/corrupt.db ] || [ "$PRISTINE_DB_SHA" != "2b48e31a12a3ab4000524d4238afc808a61aeea165deed26b365c50c803674d4" ]; then
    echo "no-modify: /app/corrupt.db missing or modified" >&2
    no_modify_broken=1
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/solve.py"
no_modify_broken = int(sys.argv[1])


def norm(obj):
    """Normalize a report so floats compare robustly."""
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {"file", "truncation", "salvaged_rows"}, obj.keys()
    f = obj["file"]
    t = obj["truncation"]
    assert set(f.keys()) == {"page_size", "header_page_count",
                             "present_page_count", "file_bytes"}, f.keys()
    assert set(t.keys()) == {"mode", "missing_bytes"}, t.keys()
    rows = []
    for r in obj["salvaged_rows"]:
        assert set(r.keys()) == {"id", "pallet", "lane", "gross_kg",
                                 "scanned_at"}, r.keys()
        rows.append((int(r["id"]), str(r["pallet"]), int(r["lane"]),
                     round(float(r["gross_kg"]), 6), str(r["scanned_at"])))
    ids = [r[0] for r in rows]
    assert ids == sorted(ids), "salvaged_rows must be sorted by id"
    return {
        "file": {k: int(f[k]) for k in f},
        "truncation": {"mode": str(t["mode"]),
                       "missing_bytes": int(t["missing_bytes"])},
        "rows": rows,
    }


def run_case(db, expected_path):
    out = "/tmp/chert_quay_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, db, out],
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
        return norm(got) == norm(want)
    except Exception:
        return False


failures = []
if no_modify_broken:
    failures.append("/app/corrupt.db modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")
else:
    # visible case: EXECUTE solve.py on the supplied input
    if not run_case("/app/corrupt.db", "/tests/expected.json"):
        failures.append("visible case failed")

    # visible-case deliverable: /app/salvaged.json must match too
    if os.path.isfile("/app/salvaged.json"):
        try:
            with open("/app/salvaged.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if norm(got) != norm(want):
                failures.append("/app/salvaged.json does not match visible expected")
        except Exception:
            failures.append("/app/salvaged.json unreadable")
    else:
        failures.append("missing /app/salvaged.json")

    # hidden cases: distinct truncated DBs with their own expecteds
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            db = os.path.join(base, "corrupt.db")
            exp = os.path.join(base, "expected.json")
            if not (os.path.isfile(db) and os.path.isfile(exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(db, exp):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
