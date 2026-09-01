#!/bin/bash
# Verifier for item-076-main: compare decode.py against the oracle on hidden streams.
mkdir -p /logs/verifier

reward=$(python3 - <<'PY'
import glob, subprocess, sys

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
print(f"{reward:.2f}")
PY
)
if [ -z "$reward" ]; then reward="0.00"; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0