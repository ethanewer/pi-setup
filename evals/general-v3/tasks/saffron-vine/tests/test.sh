#!/bin/bash
# saffron-vine verifier. Runs as root after the agent finishes. Enforces the
# no-modify rule on /app/case, validates the visible artifact set, EXECUTES the
# deliverable (/app/restore.py) on the visible case and on every hidden fixture,
# and validates each produced artifact set with /tests/verify.py.
# Writes 0/1 to /logs/verifier/reward.txt.
set -uo pipefail

mkdir -p /logs/verifier
REWARD=0
reason=""

# ---- integrity of the supplied fixture (no-modify rule) --------------------
CASE_DIR=/app/case
if [ ! -f "$CASE_DIR/meta.json" ] || [ ! -f "$CASE_DIR/base_state.pt" ]; then
  reason="visible case fixture missing"
fi

if [ -z "$reason" ] && [ ! -f /app/restore.py ]; then
  reason="restore.py missing"
fi

if [ -z "$reason" ]; then
  # visible-case deliverables must exist in /app (produced by the agent's run)
  for f in /app/restore.py \
           /app/adapter/adapter_config.json \
           /app/adapter/adapter_weights.safetensors \
           /app/adapter/feature_spec.json \
           /app/adapter_merged.pt \
           /app/eval_metrics.json; do
    [ -f "$f" ] || { reason="$reason missing-$f"; }
  done
fi

# ---- visible case: execute the deliverable + verify artifacts ---------------
if [ -z "$reason" ]; then
  rm -rf /tmp/vis_out
  if ! python3 /app/restore.py /app/case /tmp/vis_out >/tmp/vis_run.log 2>&1; then
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
    if ! python3 /app/restore.py "$d" "$out" >"/tmp/h_run_$name.log" 2>&1; then
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
