#!/bin/bash
#
# tb3-vellum-poster verifier. Executes the deliverable
# /app/render_poster.py on the visible spec and on the hidden specs under
# /tests/hidden/specs/, parses each produced SVG (xml.etree), and compares
# it against an independent recompute of the documented layout formulas.
# Also validates the /app/poster.svg deliverable against the visible spec
# and re-runs one case to enforce byte-identical (deterministic) output.
# Writes REWARD (0/1) to /logs/verifier/reward.txt on EVERY exit path.
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

log() { echo "tb3-vellum-poster verify: $*" >&2; }

# ---------------------------------------------------------------------------
# 1. Deliverable present.
# ---------------------------------------------------------------------------
if [ ! -s /app/render_poster.py ]; then
  overall=0; msgs="$msgs missing:render_poster.py"
fi

# ---------------------------------------------------------------------------
# 2. Full probe battery (visible + hidden + poster.svg + determinism).
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  if ! $TIMEOUT_CMD 240 python3 /tests/hidden/verify_poster.py >/tmp/vellum_verify.log 2>&1; then
    overall=0; msgs="$msgs probe:failed"
    tail -20 /tmp/vellum_verify.log >&2 2>/dev/null || true
  else
    log "probe battery passed"
  fi
fi

if [ "$overall" = "1" ]; then
  log "all checks passed"
else
  log "FAIL${msgs:+:${msgs}}"
fi
finalize_reward
exit 0