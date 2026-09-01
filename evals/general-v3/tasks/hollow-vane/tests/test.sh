#!/bin/bash
# Verifier for hollow-vane: checks the visible deliverables are present and
# correct, ENFORCES the no-modify rule on the supplied /app/clues tree, and
# EXECUTES the deliverable program (/app/payload.py) on the visible clue set
# and on every hidden clue set in /tests/hidden, comparing the derived payload
# to each case's reference. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine combined sha256 of the supplied /app/clues tree (the instruction
# tells the agent not to modify it; tampering defeats the visible-case check).
PRISTINE_CLUES_SHA="3ed7d09bb819db46fadd4a5f6ed8f8617b65d7ae11b0eb7a2cf51b17d5bdd5eb"

clues_ok=1
if [ ! -d /app/clues ]; then
    echo "no-modify: /app/clues missing" >&2
    clues_ok=0
else
    actual="$(cd /app/clues && find . -type f | LC_ALL=C sort | xargs sha256sum | sha256sum | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_CLUES_SHA" ]; then
        echo "no-modify: /app/clues was modified" >&2
        clues_ok=0
    fi
fi

python3 - "$clues_ok" <<'PY'
import json
import os
import subprocess
import sys

SOLVE = "/app/payload.py"
ANSWER = "/app/answer.txt"
clues_ok = int(sys.argv[1])

failures = []
if clues_ok:
    pass
else:
    failures.append("visible clues modified or missing (no-modify rule)")


def run_case(clue_root, expected_path):
    """EXECUTE the deliverable on a clue set and compare stdout to the
    reference payload."""
    out = "/tmp/hollow_vane_verify_out.txt"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, clue_root, out],
            capture_output=True, text=True, timeout=120,
        )
    except Exception as exc:
        return ["payload.py failed to run on %s (%s)" % (clue_root, exc)]
    if r.returncode != 0:
        return ["payload.py exited %d on %s" % (r.returncode, clue_root)]
    try:
        with open(expected_path) as fh:
            want = json.load(fh)["payload"]
        assert isinstance(want, int)
    except Exception as exc:
        return ["bad expected fixture %s (%s)" % (expected_path, exc)]
    got = r.stdout.strip()
    if got != str(want):
        return ["%s: stdout %r != expected %r" % (clue_root, got, want)]
    # optional outfile contract must hold as well
    try:
        with open(out) as fh:
            file_text = fh.read()
        if file_text != str(want) + "\n":
            return ["%s: outfile content %r wrong" % (clue_root, file_text)]
    except Exception as exc:
        return ["%s: outfile not written (%s)" % (clue_root, exc)]
    return []


if not os.path.isfile(SOLVE):
    failures.append("missing /app/payload.py")
else:
    # --- visible case: EXECUTE payload.py on the supplied /app/clues ---
    if os.path.isdir("/app/clues") and os.path.isfile("/tests/expected.json"):
        failures.extend(run_case("/app/clues", "/tests/expected.json"))
    else:
        failures.append("visible inputs missing")

    # --- visible-case deliverable: /app/answer.txt must match ---
    try:
        with open("/tests/expected.json") as fh:
            want = json.load(fh)["payload"]
        with open(ANSWER) as fh:
            got = fh.read().strip()
        if got != str(want):
            failures.append("answer.txt %r != expected %r" % (got, want))
    except Exception as exc:
        failures.append("answer.txt unreadable or missing (%s)" % exc)

    # --- hidden cases: distinct clue sets with their own references ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            exp = os.path.join(base, "expected.json")
            clues = os.path.join(base, "clues")
            if not os.path.isdir(clues):
                clues = base  # clue artifacts live directly in the case dir
            if not (os.path.isdir(clues) and os.path.isfile(exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            failures.extend(run_case(clues, exp))
    else:
        failures.append("no hidden cases directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0