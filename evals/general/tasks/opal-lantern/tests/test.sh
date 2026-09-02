#!/bin/bash
# Verifier for opal-lantern: checks the visible deliverables, ENFORCES the
# no-modify rule on /app/survey.jsonl, and EXECUTES the deliverable program
# (/app/export_locale.py) on the visible case and every hidden case in
# /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_SURVEY_SHA="ea25763009492b8ab68684f18da40b8f89e9b1c0fb4008a572e3eadcc50dc688"

no_modify_broken=0
if [ ! -f /app/survey.jsonl ]; then
    echo "no-modify: /app/survey.jsonl missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/survey.jsonl | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_SURVEY_SHA" ]; then
        echo "no-modify: /app/survey.jsonl was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/export_locale.py"
no_modify_broken = int(sys.argv[1])
failures = []


def load_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def load_jsonl(path):
    rows = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            if line.strip():
                rows.append(json.loads(line))
    return rows


def run_case(inp, locale, columns, expected_path):
    out = "/tmp/opal_lantern_verify_out.jsonl"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, "--input", inp, "--locale", locale,
             "--columns", columns, "--output", out],
            capture_output=True, text=True, timeout=120,
        )
    except Exception as exc:
        failures.append("exec error: %r" % exc)
        return
    if r.returncode != 0:
        failures.append("exit=%d stderr=%s" % (r.returncode, r.stderr[-300:]))
        return
    if not os.path.isfile(out):
        failures.append("no output file for locale=%s" % locale)
        return
    try:
        got = load_jsonl(out)
        want = load_json(expected_path)
    except Exception as exc:
        failures.append("parse error: %r" % exc)
        return
    if got != want:
        failures.append("mismatch for locale=%s columns=%s "
                        "(got %d rows, want %d)" %
                        (locale, columns, len(got), len(want)))


if no_modify_broken:
    failures.append("visible input modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/export_locale.py")
else:
    # --- visible case: EXECUTE the deliverable on the live supplied inputs ---
    run_case("/app/survey.jsonl", "fr-FR",
             "record_id,meta.site,meta.banding.ring,species,count",
             "/tests/expected.json")

    # --- visible deliverable: /app/exports/survey_fr.jsonl must match ---
    if os.path.isfile("/app/exports/survey_fr.jsonl"):
        try:
            got = load_jsonl("/app/exports/survey_fr.jsonl")
            want = load_json("/tests/expected.json")
            if got != want:
                failures.append("/app/exports/survey_fr.jsonl mismatch")
        except Exception as exc:
            failures.append("survey_fr.jsonl unreadable: %r" % exc)
    else:
        failures.append("missing /app/exports/survey_fr.jsonl")

    # --- hidden cases ---
    hidden_dir = "/tests/hidden"
    cases = sorted(d for d in os.listdir(hidden_dir)
                   if os.path.isdir(os.path.join(hidden_dir, d)))
    if not cases:
        failures.append("no hidden cases present")
    for c in cases:
        base = os.path.join(hidden_dir, c)
        try:
            cfg = load_json(os.path.join(base, "case.json"))
            inp = os.path.join(base, cfg["input"])
            exp = os.path.join(base, "expected.json")
        except Exception as exc:
            failures.append("hidden '%s' malformed: %r" % (c, exc))
            continue
        if not (os.path.isfile(inp) and os.path.isfile(exp)):
            failures.append("hidden '%s' missing files" % c)
            continue
        run_case(inp, cfg["locale"], cfg["columns"], exp)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
