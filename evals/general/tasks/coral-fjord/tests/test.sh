#!/bin/bash
# coral-fjord verifier. Runs as root after the agent finishes. Enforces the
# no-modify rule on the supplied /app/pipeline.py API contract, validates the
# visible artifacts, EXECUTES the deliverable (/app/train_score.py) on the
# visible case and on every hidden fixture, and validates each artifact set
# with /tests/verify.py (gradient-flow audit + targets). Writes 0/1 to
# /logs/verifier/reward.txt.
set -uo pipefail

mkdir -p /logs/verifier
REWARD=0
reason=""

# ---- visible deliverables present ------------------------------------------
for f in /app/pipeline.py /app/train_score.py /app/model.pt \
         /app/training_report.json; do
  [ -f "$f" ] || { reason="$reason missing-$f"; }
done

# ---- visible case: execute the deliverable + verify -------------------------
if [ -z "$reason" ]; then
  rm -rf /tmp/vis_out
  if ! python3 /app/train_score.py /app/case /tmp/vis_out >/tmp/vis_run.log 2>&1; then
    reason="visible-run-failed"
    sed -n '1,30p' /tmp/vis_run.log
  elif ! python3 /tests/verify.py /app/case /tmp/vis_out >/tmp/vis_ver.log 2>&1; then
    reason="visible-verify-failed"
    sed -n '1,30p' /tmp/vis_ver.log
  fi
fi

# ---- hidden cases: execute the deliverable on fresh fixtures ----------------
if [ -z "$reason" ]; then
  for d in /tests/hidden/*/; do
    name=$(basename "$d")
    out=/tmp/hout_$name
    rm -rf "$out"
    if ! python3 /app/train_score.py "$d" "$out" >"/tmp/h_run_$name.log" 2>&1; then
      reason="$reason hidden-$name-run-failed"
      sed -n '1,30p' "/tmp/h_run_$name.log"
    elif ! python3 /tests/verify.py "$d" "$out" >"/tmp/h_ver_$name.log" 2>&1; then
      reason="$reason hidden-$name-verify-failed"
      sed -n '1,30p' "/tmp/h_ver_$name.log"
    fi
  done
fi

if [ -z "$reason" ]; then
  REWARD=1
fi

echo "$REWARD" > /logs/verifier/reward.txt
echo "REWARD=$REWARD reason=${reason:-ok}"
exit 0
