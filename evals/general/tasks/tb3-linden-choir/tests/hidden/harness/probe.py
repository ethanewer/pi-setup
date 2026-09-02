#!/usr/bin/env python3
"""Verifier probe for tb3-linden-choir.

Executes the deliverable /app/analyze.py on the visible fixture (/app/score.json)
and on every hidden score under /tests/hidden/cases, twice per score
(determinism), and compares each output against an independent recomputation
(harness/refanalyze.py) of the documented ruleset — never against fixed answer
files. Also validates the deliverable /app/analysis.json against the visible
recompute, and feeds malformed inputs that must be rejected (non-zero exit,
no output file). Exits 0 iff every check passes.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import refanalyze as REF

ANALYZE = "/app/analyze.py"
VISIBLE = "/app/score.json"
DELIVERABLE = "/app/analysis.json"
CASES = "/tests/hidden/cases"
WORK = "/tmp/lc"

failures = []


def log(msg):
    print("linden-choir probe:", msg, file=sys.stderr)


def run_analyze(score_path, out_path):
    """Execute the deliverable CLI; return (returncode, stderr-last-line)."""
    try:
        r = subprocess.run(["python3", ANALYZE, score_path, out_path],
                           capture_output=True, text=True, timeout=90)
        return r.returncode, (r.stderr or "").strip().splitlines()[-1] if (r.stderr or "").strip() else ""
    except Exception as exc:
        return None, str(exc)


def check_ok(score_path, expected, label, base):
    """Run the CLI twice; both runs must exit 0 and equal the reference."""
    os.makedirs(WORK, exist_ok=True)
    prev = None
    for trial in (1, 2):
        out = os.path.join(WORK, "%s_t%d.json" % (base, trial))
        if os.path.exists(out):
            os.remove(out)
        rc, _ = run_analyze(score_path, out)
        if rc is None:
            failures.append("%s: analyze.py failed to launch" % label)
            return
        if rc != 0:
            failures.append("%s: analyze.py exited %d" % (label, rc))
            return
        if not os.path.exists(out):
            failures.append("%s: no output file written on success" % label)
            return
        try:
            with open(out, "r", encoding="utf-8") as fh:
                got = json.load(fh)
        except Exception as exc:
            failures.append("%s: output is not valid JSON: %s" % (label, exc))
            return
        if got != expected:
            failures.append("%s: analysis mismatch vs reference (trial %d)" % (label, trial))
            return
        if prev is not None and got != prev:
            failures.append("%s: non-deterministic output across runs" % label)
            return
        prev = got


def expect_error(score_path, label):
    """Malformed input must be rejected: exit != 0 and no output file."""
    os.makedirs(WORK, exist_ok=True)
    out = os.path.join(WORK, "%s_err.json" % label)
    if os.path.exists(out):
        os.remove(out)
    rc, _ = run_analyze(score_path, out)
    if rc is None:
        failures.append("%s: launch failed (should reject cleanly)" % label)
    elif rc == 0:
        failures.append("%s: malformed input accepted (exit 0)" % label)
    if os.path.exists(out):
        failures.append("%s: output file created despite error" % label)


# --- 1. Deliverable /app/analysis.json equals the visible recomputation.
try:
    with open(VISIBLE, "r", encoding="utf-8") as fh:
        visible = json.load(fh)
    visible_expected = REF.analyze(visible)
    with open(DELIVERABLE, "r", encoding="utf-8") as fh:
        delivered = json.load(fh)
    if delivered != visible_expected:
        failures.append("/app/analysis.json != recomputation of visible score")
except Exception as exc:
    failures.append("deliverable /app/analysis.json unreadable/invalid: %s" % exc)

# --- 2. Hidden cases (and the visible via the CLI), twice each.
if not os.path.isdir(CASES):
    failures.append("no hidden cases directory")
else:
    names = sorted(os.listdir(CASES))
    if not names:
        failures.append("hidden cases directory is empty")
    for name in names:
        path = os.path.join(CASES, name, "score.json")
        if not os.path.isfile(path):
            failures.append("hidden case '%s' has no score.json" % name)
            continue
        try:
            with open(path, "r", encoding="utf-8") as fh:
                score = json.load(fh)
            expected = REF.analyze(score)
        except Exception as exc:
            failures.append("hidden case '%s' not analyzable: %s" % (name, exc))
            continue
        check_ok(path, expected, "hidden '%s'" % name, "h_%s" % name)
    check_ok(VISIBLE, visible_expected, "visible via CLI", "v_visible")

# --- 3. Malformed inputs must be rejected (exit != 0, no output file).
def write_tmp(name, text):
    path = os.path.join("/tmp", name)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    return path

bad_note = write_tmp("lc_badnote.json",
                     '{"key":"Cmaj","chords":[{"beat":1,"duration":1,"notes":["C4","H4","E4"]}]}')
expect_error(bad_note, "badnote")

bad_chord = write_tmp("lc_badchord.json",
                      '{"key":"Cmaj","chords":[{"beat":1,"duration":1,"notes":["C4","D#4","F#4"]}]}')
expect_error(bad_chord, "badchord")

bad_key = write_tmp("lc_badkey.json", '{"key":"Hmaj","chords":[]}')
expect_error(bad_key, "badkey")

bad_fields = write_tmp("lc_badfields.json",
                       '{"key":"Cmaj","chords":[{"beat":1,"notes":["C4","E4","G4"]}]}')
expect_error(bad_fields, "badfields")

bad_json = write_tmp("lc_badjson.json", '{"key": "Cmaj", "chords": [}')
expect_error(bad_json, "badjson")

expect_error(os.path.join("/tmp", "lc_nosuchfile.json"), "missingfile")

# --- report
if failures:
    for f in failures:
        log("FAIL " + f)
    sys.exit(1)
log("all checks passed")
sys.exit(0)