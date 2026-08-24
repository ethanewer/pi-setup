#!/bin/bash
# Verifier for item-011-hard: compare port.py output byte-for-byte to the
# ground-truth report for the hidden test input.
#
# Note: the source reference.cob does not compile cleanly under the GnuCOBOL
# shipped on this platform (its `WRITE`/`STRING` runtime layout is unreliable,
# so compiling it live does not yield the documented newline-delimited 46-byte
# report). We instead ship the independently-derived ground-truth report for
# the hidden input as tests/reference_report.txt (checked byte-for-byte, which
# is the same contract).
mkdir -p /logs/verifier
reward=0

if [ ! -f /app/port.py ] || [ ! -s /app/port.py ]; then
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

# The hidden test input is delivered at /tests/test_input.dat.
cp /tests/test_input.dat /app/port_input.dat
python3 /app/port.py

if [ -f /app/port_output.txt ]; then
  python3 - <<'PYEOF'
exp = open("/tests/reference_report.txt", "rb").read()
got = open("/app/port_output.txt", "rb").read()
norm = lambda b: b.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
reward = 1 if norm(exp) == norm(got) else 0
open("/logs/verifier/reward.txt", "w").write(str(reward))
PYEOF
else
  echo 0 > /logs/verifier/reward.txt
fi