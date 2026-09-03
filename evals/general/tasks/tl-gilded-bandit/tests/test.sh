#!/bin/bash
#
# tl-gilded-bandit verifier.  Executes the deliverables: loads /app/policy.py
# and runs it inside the verifier's own independent simulation on the visible
# fixture (cross-checking /app/eval_report.json against a re-run) and on the
# hidden parameter sets in /tests/hidden/cases.  Writes 1/0 to
# /logs/verifier/reward.txt on EVERY exit path (EXIT trap); defaults to 0.
set -u

mkdir -p /logs/verifier

TIMEOUT_CMD=$(command -v timeout || true)
[ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""

overall=1
msgs=""

finalize_reward() {
  if [ "${overall:-0}" = "1" ]; then
    printf 1 > /logs/verifier/reward.txt
  else
    printf 0 > /logs/verifier/reward.txt
  fi
}
trap 'finalize_reward' EXIT
printf 0 > /logs/verifier/reward.txt

log() { echo "tl-gilded-bandit verify: $*" >&2; }

# Deliverables must exist before the probe runs.
if [ ! -f /app/policy.py ]; then
  overall=0; msgs="$msgs missing:policy.py"
fi
if [ ! -f /app/eval_report.json ]; then
  overall=0; msgs="$msgs missing:eval_report.json"
fi

# Main probe: independent simulation + report recomputation + hidden sets.
if [ "$overall" = "1" ]; then
  if $TIMEOUT_CMD 150 python3 /tests/hidden/probe_main.py >/tmp/gb_probe.log 2>&1; then
    log "all checks passed"
  else
    overall=0
    msgs="$msgs probe-failed"
    tail -40 /tmp/gb_probe.log >&2 2>/dev/null || true
  fi
fi

if [ "$overall" = "1" ]; then
  log "reward=1"
else
  log "FAIL${msgs:+:${msgs}}"
fi
finalize_reward
exit 0