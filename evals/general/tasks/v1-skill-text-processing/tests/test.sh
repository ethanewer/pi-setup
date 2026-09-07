#!/bin/bash
# Verifier for skill-text-processing. Recomputes expected word/line counts
# from /app/input.txt and compares to the agent's /app/summary.json.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier

reward=$(python3 - <<'PY'
import json, sys

def load(p):
    try:
        with open(p) as f:
            return json.load(f)
    except Exception:
        return None

got = load("/app/summary.json")
try:
    with open("/app/input.txt") as f:
        text = f.read()
except Exception:
    text = ""

expected = {
    "words": len(text.split()),
    "lines": len([ln for ln in text.split("\n") if ln.strip()]),
}

ok = (isinstance(got, dict)
      and got.get("words") == expected["words"]
      and got.get("lines") == expected["lines"])
print("1" if ok else "0")
sys.exit(0)
PY
)
if [ -z "$reward" ]; then reward="0"; fi
echo "$reward" > /logs/verifier/reward.txt