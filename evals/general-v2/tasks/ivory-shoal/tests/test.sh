#!/bin/bash
# Verifier for ivory-shoal: checks the visible deliverable /app/plasmid_out.txt
# and EXECUTES /app/plasmid.py on every hidden parameter case, validating the
# produced tags property-by-property (format, alphabet, all four bases,
# homopolymer cap, and every circular window's pair percentage). Writes 0/1 to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json, os, subprocess, sys
from decimal import Decimal
from fractions import Fraction

SOLVE = "/app/plasmid.py"
failures = []


def check_tag(path, length, window, lo, hi, pair):
    """Return None if the tag at <path> satisfies every rule, else an error string."""
    if not os.path.isfile(path):
        return "no output file"
    try:
        raw = open(path, "rb").read().decode("utf-8")
    except Exception as e:
        return "unreadable: %r" % (e,)
    if not raw.endswith("\n") or raw.count("\n") != 1:
        return "file must be exactly one line plus one trailing newline"
    tag = raw[:-1]
    if len(tag) != length:
        return "length %d != expected %d" % (len(tag), length)
    if set(tag) - set("ACGT"):
        return "alphabet violation: %s" % sorted(set(tag) - set("ACGT"))
    if not all(b in tag for b in "ACGT"):
        return "not all four bases present"
    extended = tag + tag[:8]
    run, max_run = 1, 1
    for i in range(1, len(extended)):
        run = run + 1 if extended[i] == extended[i - 1] else 1
        max_run = max(max_run, run)
    if max_run > 4:
        return "homopolymer run of %d" % max_run
    loF, hiF = Fraction(Decimal(str(lo))), Fraction(Decimal(str(hi)))
    pair = set(pair)
    circ = tag + tag
    for start in range(length):
        cnt = sum(1 for b in circ[start:start + window] if b in pair)
        pct = Fraction(100 * cnt, window)
        if not (loF <= pct <= hiF):
            return "window at %d has pair fraction %s outside [%s, %s]" % (
                start, float(pct), lo, hi)
    return None


if not os.path.isfile(SOLVE):
    failures.append("missing /app/plasmid.py")
else:
    # visible deliverable (produced by the documented visible run)
    err = check_tag("/app/plasmid_out.txt", 1200, 80, "32", "44", "GC")
    if err:
        failures.append("visible /app/plasmid_out.txt: " + err)

    # hidden cases: execute the deliverable, then validate its output
    hidden = "/tests/hidden"
    cases = sorted(os.listdir(hidden)) if os.path.isdir(hidden) else []
    if not cases:
        failures.append("no hidden cases present")
    for case in cases:
        params_p = os.path.join(hidden, case, "params.json")
        try:
            p = json.load(open(params_p))
            length, window = int(p["length"]), int(p["window"])
            lo, hi, pair = str(p["lo"]), str(p["hi"]), str(p["pair"]).upper()
        except Exception:
            failures.append("hidden '%s' malformed params" % case)
            continue
        out = "/tmp/ivory_shoal_out_%s.txt" % case
        if os.path.exists(out):
            os.remove(out)
        try:
            r = subprocess.run(
                [sys.executable, SOLVE, out, str(length), str(window), lo, hi, pair],
                capture_output=True, text=True, timeout=120)
        except Exception as e:
            failures.append("hidden '%s' execution error: %r" % (case, e))
            continue
        if r.returncode != 0:
            failures.append("hidden '%s' exited %d" % (case, r.returncode))
            continue
        err = check_tag(out, length, window, lo, hi, pair)
        if err:
            failures.append("hidden '%s': %s" % (case, err))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
