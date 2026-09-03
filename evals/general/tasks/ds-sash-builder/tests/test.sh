#!/bin/bash
#
# ds-sash-builder verifier. Executes the deliverables /app/qb/window.py and
# /app/demo_out.sql: byte-checks the shipped builder files against pristine
# copies, then runs the hidden probe which (a) re-renders the visible demo's
# DEMO_SPECS with an independent reference implementation and compares
# python3 /app/demo.py stdout and /app/demo_out.sql byte-for-byte, (b) runs
# ~20 hidden usage-matrix queries through the real builder API and compares
# canonical .sql() strings byte-for-byte, and (c) spot-checks the OverSpec /
# window_item API surface including ValueError validation. Writes REWARD
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

log() { echo "ds-sash-builder verify: $*" >&2; }

# ---------------------------------------------------------------------------
# 1. Tamper detection: shipped builder files must be byte-identical to the
#    pristine copies baked into the image.
# ---------------------------------------------------------------------------
for f in qb/__init__.py qb/core.py demo.py; do
  if ! cmp -s "/app/$f" "/opt/pristine/$f"; then
    overall=0; msgs="$msgs tampered:/app/$f"
  fi
done

# ---------------------------------------------------------------------------
# 2. Deliverable /app/qb/window.py present and non-empty.
# ---------------------------------------------------------------------------
if [ ! -s /app/qb/window.py ]; then
  overall=0; msgs="$msgs missing-or-empty:/app/qb/window.py"
fi

# ---------------------------------------------------------------------------
# 3. Hidden probe: visible recheck + hidden matrices + API surface (this
#    also executes /app/qb/window.py and re-checks /app/demo_out.sql).
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  if ! $TIMEOUT_CMD 240 python3 /tests/hidden/probe_window.py >/tmp/ds_probe.log 2>&1; then
    overall=0; msgs="$msgs probe:failed"
    tail -12 /tmp/ds_probe.log >&2 2>/dev/null || true
  fi
fi

if [ "$overall" = "1" ]; then
  log "all checks passed"
else
  log "FAIL${msgs:+:${msgs}}"
fi
finalize_reward
exit 0