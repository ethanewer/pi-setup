#!/bin/bash
#
# pearl-gasket verifier.
# Executes the deliverable /app/analyze.py on the visible fixture and on the
# hidden scores under /tests/hidden/cases, twice each (determinism), comparing
# every output against an independent recomputation inside the probe. Also
# validates the deliverable /app/analysis.json against the visible recompute
# and requires non-zero exits for malformed inputs. Writes REWARD (0/1) to
# /logs/verifier/reward.txt on EVERY exit path (EXIT trap).
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

log() { echo "pearl-gasket verify: $*" >&2; }

# ---------------------------------------------------------------------------
# 1. Deliverables present and non-empty.
# ---------------------------------------------------------------------------
if [ ! -s /app/analyze.py ]; then
  overall=0; msgs="$msgs missing:analyze.py"
fi
if [ ! -s /app/analysis.json ]; then
  overall=0; msgs="$msgs missing:analysis.json"
fi

# ---------------------------------------------------------------------------
# 2. Hidden probe: executes /app/analyze.py, recomputes the reference
#    independently, checks determinism and malformed-input rejection.
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  if ! $TIMEOUT_CMD 120 python3 /tests/hidden/harness/probe.py >/tmp/lc_probe.log 2>&1; then
    overall=0; msgs="$msgs probe:failed"
    tail -12 /tmp/lc_probe.log >&2 2>/dev/null || true
  fi
fi

if [ "$overall" = "1" ]; then
  log "all checks passed"
else
  log "FAIL${msgs:+:${msgs}}"
fi
finalize_reward
exit 0