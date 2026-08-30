#!/bin/bash
# larch-cipher verifier. Runs as root after the agent finishes. Executes the
# deliverable (/app/finetune.py) and validates every persisted artifact, both on
# the agent's /app outputs and replayed on the hidden fixtures. Writes 0/1 to
# /logs/verifier/reward.txt.
set -uo pipefail

cd /app
mkdir -p /logs/verifier
REWARD=0
reason=""

# ---- visible deliverable present, then validated -------------------------
if [ ! -f /app/finetune.py ]; then reason="finetune.py missing"; fi

if [ -z "$reason" ]; then
  if python3 /tests/verify.py /app/case /app >/tmp/vis.log 2>&1; then
    : # visible PASS
  else
    reason="visible-verify-failed"
    sed -n '1,30p' /tmp/vis.log
  fi
fi

# ---- replay the program on every hidden fixture --------------------------
ALLPASS=1
for d in /tests/hidden/*/; do
  name=$(basename "$d")
  out=/tmp/hout_$name
  rm -rf "$out"
  if ! python3 /app/finetune.py "$d" "$out" >/tmp/h_$name.log 2>&1; then
    reason="$reason hidden-$name-run-failed"
    ALLPASS=0
    sed -n '1,30p' /tmp/h_$name.log
  elif ! python3 /tests/verify.py "$d" "$out" >/tmp/hv_$name.log 2>&1; then
    reason="$reason hidden-$name-verify-failed"
    ALLPASS=0
    sed -n '1,30p' /tmp/hv_$name.log
  else
    grep -q "RESULT: PASS" /tmp/hv_$name.log || { ALLPASS=0; reason="$reason hidden-$name-notpass"; }
  fi
done

if [ -z "$reason" ] && [ "$ALLPASS" = 1 ]; then
  REWARD=1
fi

echo "$REWARD" > /logs/verifier/reward.txt
echo "REWARD=$REWARD reason=${reason:-ok}"
exit 0