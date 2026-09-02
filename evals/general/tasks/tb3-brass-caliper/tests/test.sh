#!/bin/bash
#
# tb3-brass-caliper verifier. Executes the deliverables: imports
# /app/cadmodel.py and re-runs every documented function on the visible spec
# and on the hidden specs in /tests/hidden/specs.json, comparing against an
# independent recompute; and checks /app/spacer_report.json against the
# verifier's own recompute of /app/specs/spacer_spec.json. Writes reward
# (0/1) to /logs/verifier/reward.txt on EVERY exit path (EXIT trap).
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

log() { echo "tb3-brass-caliper verify: $*" >&2; }

# ---------------------------------------------------------------------------
# 1. Deliverables present and non-empty.
# ---------------------------------------------------------------------------
if [ ! -s /app/cadmodel.py ]; then
  overall=0; msgs="$msgs missing:cadmodel.py"
fi
if [ ! -s /app/spacer_report.json ]; then
  overall=0; msgs="$msgs missing:spacer_report.json"
fi

# ---------------------------------------------------------------------------
# 2. Execute deliverables against visible + hidden specs via the probe.
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  if ! $TIMEOUT_CMD 120 python3 /tests/hidden/probe.py >/tmp/bc_probe.log 2>&1; then
    overall=0; msgs="$msgs probe:failed"
    tail -12 /tmp/bc_probe.log >&2 2>/dev/null || true
  fi
fi

if [ "$overall" = "1" ]; then
  log "all checks passed"
else
  log "FAIL${msgs:+:${msgs}}"
fi
finalize_reward
exit 0