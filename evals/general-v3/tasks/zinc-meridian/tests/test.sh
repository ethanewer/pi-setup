#!/bin/bash
# Verifier for zinc-meridian: checks the visible deliverables, ENFORCES the
# no-modify rule on the supplied /app inputs, and EXECUTES the deliverable
# program (/app/screen.py) on the visible case and every hidden case in
# /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_COMPOUNDS_SHA="049db69527773e477064d89ddde056ef96b29d028b15ca4a1cc7dc7b2d97d0e7"
PRISTINE_MASSES_SHA="98b481df99f52d75847f49026b0e5696481e63b46ac69d40adf4d4b6a40d04ae"
PRISTINE_TARGET_SHA="1bddf64c6fc466ed4892050d440223b2c7d32014d0fd161ec56e5b6d364831bb"

no_modify_broken=0
check_pristine() {
    local path="$1" want="$2"
    if [ ! -f "$path" ]; then
        echo "no-modify: $path missing" >&2
        no_modify_broken=1
        return
    fi
    local actual
    actual="$(sha256sum "$path" | awk '{print $1}')"
    if [ "$actual" != "$want" ]; then
        echo "no-modify: $path was modified" >&2
        no_modify_broken=1
    fi
}
check_pristine /app/compounds.json "$PRISTINE_COMPOUNDS_SHA"
check_pristine /app/atomic_masses.json "$PRISTINE_MASSES_SHA"
check_pristine /app/target.json "$PRISTINE_TARGET_SHA"

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/screen.py"
no_modify_broken = int(sys.argv[1])
failures = []


def load_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def norm(obj):
    """Normalize a report so floats compare exactly at the documented rounding."""
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {"descriptor", "target", "tolerance",
                               "matches", "report"}, obj.keys()
    assert obj["descriptor"] == "molecular_weight", obj["descriptor"]
    rep = obj["report"]
    assert set(rep.keys()) == {"rows_in", "rows_parsed", "rows_rejected",
                               "rejected_ids", "matched"}, rep.keys()
    matches = []
    for m in obj["matches"]:
        assert set(m.keys()) == {"id", "name", "formula",
                                 "molecular_weight", "distance",
                                 "score"}, m.keys()
        matches.append((str(m["id"]), str(m["name"]), str(m["formula"]),
                        round(float(m["molecular_weight"]), 4),
                        round(float(m["distance"]), 4),
                        round(float(m["score"]), 6)))
    return {
        "target": round(float(obj["target"]), 4),
        "tolerance": round(float(obj["tolerance"]), 4),
        "matches": matches,
        "report": {
            "rows_in": int(rep["rows_in"]),
            "rows_parsed": int(rep["rows_parsed"]),
            "rows_rejected": int(rep["rows_rejected"]),
            "rejected_ids": sorted(str(i) for i in rep["rejected_ids"]),
            "matched": int(rep["matched"]),
        },
    }


def run_case(compounds, masses, target, expected_path):
    out = "/tmp/zinc_meridian_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, "--compounds", compounds,
             "--masses", masses, "--target", target, "--output", out],
            capture_output=True, text=True, timeout=120,
        )
    except Exception as exc:
        failures.append("exec error: %r" % exc)
        return
    if r.returncode != 0:
        failures.append("exit=%d stderr=%s" % (r.returncode, r.stderr[-300:]))
        return
    if not os.path.isfile(out):
        failures.append("no output for %s" % compounds)
        return
    try:
        got = norm(load_json(out))
        want = norm(load_json(expected_path))
    except Exception as exc:
        failures.append("parse error: %r" % exc)
        return
    if got != want:
        failures.append("mismatch for %s" % compounds)


if no_modify_broken:
    failures.append("visible input modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/screen.py")
else:
    # --- visible case: EXECUTE the deliverable on the live supplied inputs ---
    run_case("/app/compounds.json", "/app/atomic_masses.json",
             "/app/target.json", "/tests/expected.json")

    # --- visible deliverable: /app/formulary.json must match ---
    if os.path.isfile("/app/formulary.json"):
        try:
            got = norm(load_json("/app/formulary.json"))
            want = norm(load_json("/tests/expected.json"))
            if got != want:
                failures.append("/app/formulary.json mismatch")
        except Exception as exc:
            failures.append("formulary.json unreadable: %r" % exc)
    else:
        failures.append("missing /app/formulary.json")

    # --- hidden cases ---
    hidden_dir = "/tests/hidden"
    cases = sorted(d for d in os.listdir(hidden_dir)
                   if os.path.isdir(os.path.join(hidden_dir, d)))
    if not cases:
        failures.append("no hidden cases present")
    for c in cases:
        base = os.path.join(hidden_dir, c)
        compounds = os.path.join(base, "compounds.json")
        target = os.path.join(base, "target.json")
        exp = os.path.join(base, "expected.json")
        masses = os.path.join(base, "masses.json")
        if not os.path.isfile(masses):
            masses = "/app/atomic_masses.json"
        if not all(os.path.isfile(p) for p in (compounds, target, exp)):
            failures.append("hidden '%s' missing files" % c)
            continue
        run_case(compounds, masses, target, exp)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
