#!/bin/bash
# Verifier for saffron-loom: checks the visible-case deliverables, ENFORCES the
# no-modify rule on the supplied /app inputs, and EXECUTES the deliverable
# program (/app/export_lang.py) on the visible case and on every hidden case in
# /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures in /app (the instruction
# tells the agent not to modify these; tampering defeats the visible check).
PRISTINE_CATALOG_SHA="bcaa9b3fe09079eb1be6eba65c1b1cfd48592ec115eef319f0530e87790c2b07"
PRISTINE_TASK_SHA="739e7fbe2f09475c950ac0e1340d88d4f7b8432a50c1ddccd957b08c79931414"

no_modify_broken=0
for pair in "/app/catalog.json:$PRISTINE_CATALOG_SHA" "/app/task.json:$PRISTINE_TASK_SHA"; do
    path="${pair%%:*}"; want="${pair##*:}"
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

SOLVE = "/app/export_lang.py"
no_modify_broken = int(sys.argv[1])
failures = []


def norm_line(line):
    """Parse one JSONL line and normalize it to a comparable tuple."""
    obj = json.loads(line)
    assert isinstance(obj, dict), obj
    return [(k, obj[k]) for k in sorted(obj)]


def read_jsonl(path):
    with open(path, "r", encoding="utf-8") as fh:
        return [norm_line(l) for l in fh if l.strip()]


def run_case(dataset, query, expected_path, expected_is_json_doc=False):
    out = "/tmp/saffron_loom_verify_out.jsonl"
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run(
        [sys.executable, SOLVE, "--input", dataset, "--query", query,
         "--output", out],
        capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0:
        return False
    try:
        got = read_jsonl(out) if os.path.exists(out) else None
        if expected_is_json_doc:
            with open(expected_path) as fh:
                want = [norm_line(json.dumps(r)) for r in json.load(fh)["rows"]]
        else:
            want = read_jsonl(expected_path)
    except Exception:
        return False
    if got is None:
        return not want  # empty expected must yield empty/missing output file
    return got == want


if no_modify_broken:
    failures.append("visible inputs modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/export_lang.py")
else:
    # --- visible case: EXECUTE export_lang.py on the live supplied inputs ---
    if not (os.path.isfile("/app/catalog.json") and os.path.isfile("/app/task.json")):
        failures.append("visible inputs missing")
    elif not run_case("/app/catalog.json", "/app/task.json", "/tests/expected.json",
                      expected_is_json_doc=True):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/fr_export.jsonl must exist and match ---
    try:
        with open("/tests/expected.json") as f:
            want_rows = [norm_line(json.dumps(r)) for r in json.load(f)["rows"]]
    except Exception:
        want_rows = None
        failures.append("visible expected unreadable")
    if want_rows is not None:
        if not os.path.isfile("/app/fr_export.jsonl"):
            failures.append("missing /app/fr_export.jsonl")
        else:
            try:
                got = read_jsonl("/app/fr_export.jsonl")
                if got != want_rows:
                    failures.append("fr_export.jsonl does not match visible expected")
            except Exception:
                failures.append("fr_export.jsonl unreadable")

    # --- hidden cases: genuinely distinct inputs with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            dataset = os.path.join(base, "dataset.json")
            query = os.path.join(base, "query.json")
            exp = os.path.join(base, "expected.jsonl")
            if not all(os.path.isfile(p) for p in (dataset, query, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(dataset, query, exp):
                failures.append("hidden case '%s' failed" % c)
    else:
        failures.append("no hidden cases directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
