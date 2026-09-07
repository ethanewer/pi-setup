#!/bin/bash
# Verifier for item-076-hard: decode.py vs oracle on hidden streams, proportional reward.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier

reward=$(python3 - <<'PY'
import glob, subprocess

def run(argv):
    try:
        r = subprocess.run(argv, capture_output=True, timeout=120)
        return r.returncode, r.stdout
    except Exception:
        return -1, b""

bins = sorted(glob.glob('/app/hidden/*.bin'))
total = len(bins)
passes = 0
for b in bins:
    rc, exp = run(['/app/decompress', b])
    if rc != 0:
        continue
    rc2, got = run(['python3', '/app/solve/decode.py', b])
    if rc2 != 0:
        continue
    if got == exp:
        passes += 1

if total == 0:
    reward = 0.0
else:
    reward = passes / total
print(1 if (reward) >= 1.0 else 0)
PY
)
if [ -z "$reward" ]; then reward="0.00"; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0