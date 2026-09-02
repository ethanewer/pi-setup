#!/bin/bash
# juniper-gasket verifier. Runs as root after the agent finishes. Enforces the
# no-modify rule on the visible case, validates the visible artifacts, then
# EXECUTES the deliverable (/app/fit_screen.py) on every hidden case and
# validates each artifact set with /tests/verify.py. Writes 0/1 to
# /logs/verifier/reward.txt.
set -uo pipefail

mkdir -p /logs/verifier
REWARD=0
reason=""

for f in /app/fit_screen.py /app/screen_model.pkl /app/screen_metrics.json; do
  [ -f "$f" ] || { reason="$reason missing-$f"; }
done

# ---- visible case: artifacts validated (case fixture must be untouched) ------
if [ -z "$reason" ]; then
  if ! python3 /tests/verify.py /app/case /app >/tmp/vis.log 2>&1; then
    reason="visible-verify-failed"
    sed -n '1,30p' /tmp/vis.log
  fi
fi

# ---- hidden cases: execute the deliverable on fresh fixtures ------------------
if [ -z "$reason" ]; then
  for d in /tests/hidden/*/; do
    name=$(basename "$d")
    out=/tmp/hout_$name
    rm -rf "$out"
    if ! python3 /app/fit_screen.py "$d" "$out" >"/tmp/h_run_$name.log" 2>&1; then
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
