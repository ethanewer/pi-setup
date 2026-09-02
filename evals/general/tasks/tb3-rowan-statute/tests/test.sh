#!/bin/bash
# Verifier for tb3-rowan-statute: runs an independent recomputation probe that
# (a) compares the visible deliverables /app/declaration.csv and
# /app/validation_report.json against a recomputation of the raw inputs,
# (b) EXECUTES the deliverable /app/build_declaration.py on a copy of the
# visible workdir and on every hidden workdir under /tests/hidden, comparing
# each output to its own recomputation. Writes 1 to /logs/verifier/reward.txt
# only when every check passes.
set -u
mkdir -p /logs/verifier
overall=0
finalize_reward() { printf "%d" "$overall" > /logs/verifier/reward.txt; }
trap 'finalize_reward' EXIT
printf 0 > /logs/verifier/reward.txt
log() { echo "tb3-rowan-statute verify: $*" >&2; }

python3 /tests/hidden/probe.py
rc=$?
if [ "$rc" -eq 0 ]; then
  overall=1
  log "all checks passed"
else
  log "probe failed (exit $rc)"
fi
finalize_reward
exit 0