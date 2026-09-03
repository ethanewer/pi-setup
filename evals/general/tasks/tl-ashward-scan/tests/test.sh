#!/bin/bash
# tl-ashward-scan verifier (tblite-skill family).
#
# Executes the deliverable /app/scan_persistence.py against the visible tree
# /app/rootfs and three hidden trees materialized by the probe, byte-checks
# idempotency, and compares every report against an independent reference
# recomputation implemented in /tests/hidden/verify_reference.py. Also
# verifies /app/findings.json equals a fresh run. Writes REWARD (0/1) to
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

log() { echo "tl-ashward-scan verify: $*" >&2; }

# ---------------------------------------------------------------------------
# 1. Deliverables present.
# ---------------------------------------------------------------------------
if [ ! -f /app/scan_persistence.py ]; then
  overall=0; msgs="$msgs missing:scan_persistence.py"
fi
if [ ! -f /app/findings.json ]; then
  overall=0; msgs="$msgs missing:findings.json"
fi

# ---------------------------------------------------------------------------
# 2. Reference probe: visible + hidden recompute, idempotency, exit codes.
#    The probe literally executes both deliverable paths (subprocess) and
#    parses/compares the JSON reports byte-and-structure exactly.
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  if ! $TIMEOUT_CMD 240 python3 /tests/hidden/verify_reference.py \
        >/tmp/ashward_verify.log 2>&1; then
    overall=0; msgs="$msgs reference-probe:failed"
    tail -25 /tmp/ashward_verify.log >&2 2>/dev/null || true
  else
    log "reference probe passed"
  fi
fi

if [ "$overall" = "1" ]; then
  log "all checks passed"
else
  log "FAIL${msgs:+:${msgs}}"
fi
finalize_reward
exit 0