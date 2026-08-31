#!/bin/bash
# Verifier for copper-vane: EXECUTES the deliverable /app/salvage.py on the
# visible fixture and on every hidden case, checks /app/salvaged.json matches
# the visible expected, and enforces the no-modify rule on /app/manifest.db.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_DB_SHA="b5b2abc9567b9bae8de3f4798c22d44e0ff78946415fd5fe7f4176f94678d115"

no_modify_broken=0
if [ ! -f /app/manifest.db ]; then
    echo "no-modify: /app/manifest.db missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/manifest.db | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_DB_SHA" ]; then
        echo "no-modify: /app/manifest.db was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/salvage.py"
no_modify_broken = int(sys.argv[1])


def norm(obj):
    """Normalize a salvage report for comparison (floats rounded to 6)."""
    assert isinstance(obj, dict), "report is not an object"
    assert set(obj.keys()) == {"diagnosis", "salvaged"}, sorted(obj.keys())
    diag = obj["diagnosis"]
    assert isinstance(diag, dict), diag
    assert set(diag.keys()) == {"mode", "page_size", "declared_pages",
                                "retained_pages", "intact_rows"}, diag
    d = {
        "mode": str(diag["mode"]),
        "page_size": int(diag["page_size"]),
        "declared_pages": int(diag["declared_pages"]),
        "retained_pages": int(diag["retained_pages"]),
        "intact_rows": int(diag["intact_rows"]),
    }
    rows = obj["salvaged"]
    assert isinstance(rows, list), rows
    norm_rows = []
    for r in rows:
        assert isinstance(r, dict), r
        assert set(r.keys()) == {"id", "crate", "origin", "weighed_on",
                                 "mass"}, sorted(r.keys())
        norm_rows.append({
            "id": int(r["id"]),
            "crate": str(r["crate"]),
            "origin": str(r["origin"]),
            "weighed_on": str(r["weighed_on"]),
            "mass": round(float(r["mass"]), 6),
        })
    assert d["intact_rows"] == len(norm_rows), (d, len(norm_rows))
    return d, norm_rows


def load_expected(path):
    with open(path) as fh:
        return norm(json.load(fh))


def run_case(db_path, expected_path):
    out = "/tmp/copper_vane_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, db_path, out],
            capture_output=True, text=True, timeout=120,
        )
    except Exception as e:
        print("run error:", e)
        return False
    if r.returncode != 0 or not os.path.exists(out):
        print("solver failed:", r.stderr[-500:])
        return False
    try:
        with open(out) as fh:
            got = norm(json.load(fh))
        return got == load_expected(expected_path)
    except Exception as e:
        print("compare error:", e)
        return False


failures = []
if no_modify_broken:
    failures.append("visible input modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/salvage.py")
else:
    # --- visible case: EXECUTE salvage.py on the shipped fixture ---
    if not run_case("/app/manifest.db", "/tests/expected.json"):
        failures.append("visible case failed")

    # --- visible deliverable: /app/salvaged.json must match too ---
    if os.path.isfile("/app/salvaged.json"):
        try:
            with open("/app/salvaged.json") as fh:
                got = norm(json.load(fh))
            if got != load_expected("/tests/expected.json"):
                failures.append("/app/salvaged.json does not match visible expected")
        except Exception as e:
            failures.append("/app/salvaged.json unreadable: %s" % e)
    else:
        failures.append("missing /app/salvaged.json")

    # --- hidden cases: distinct truncated databases with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            db = os.path.join(base, "manifest.db")
            exp = os.path.join(base, "expected.json")
            if not (os.path.isfile(db) and os.path.isfile(exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(db, exp):
                failures.append("hidden case '%s' failed" % c)
    else:
        failures.append("no hidden cases directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
