#!/bin/bash
#
# ember-spire verifier. Executes the deliverable /app/render_chart.py
# through the hidden probe, which recomputes every expected output with its
# own independent reference engine (visible chart into fresh dirs, the
# /app/rendered deliverable, hidden conflict/null/merge charts, empty charts,
# ~15 documented error cases with exact exit codes and stderr tokens, usage
# errors) and compares exact canonical JSON bytes and file sets. Writes
# REWARD (0/1) to /logs/verifier/reward.txt on every exit path (EXIT trap).
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

log() { echo "ember-spire verify: $*" >&2; }

# The probe resolves relative --values paths against the working directory.
cd /app || { overall=0; msgs="$msgs cannot-cd-app"; }

# 1. Deliverable present and syntactically valid.
if [ ! -s /app/render_chart.py ]; then
  overall=0; msgs="$msgs missing:render_chart.py"
else
  if ! $TIMEOUT_CMD 60 python3 -m py_compile /app/render_chart.py \
        >/tmp/dsmm_compile.log 2>&1; then
    overall=0; msgs="$msgs render_chart.py:compile-failed"
    tail -5 /tmp/dsmm_compile.log >&2 2>/dev/null || true
  fi
fi

# 2. Hidden probe suite (independent reference engine + all cases).
if [ "$overall" = "1" ]; then
  if ! $TIMEOUT_CMD 240 python3 /tests/hidden/probe.py >/tmp/dsmm_probe.log 2>&1; then
    overall=0; msgs="$msgs probe:failed"
    tail -20 /tmp/dsmm_probe.log >&2 2>/dev/null || true
  fi
fi

if [ "$overall" = "1" ]; then
  log "all checks passed"
else
  log "FAIL${msgs:+:${msgs}}"
fi
finalize_reward
exit 0