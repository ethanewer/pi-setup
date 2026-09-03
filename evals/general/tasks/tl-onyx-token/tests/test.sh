#!/bin/bash
#
# tl-onyx-token verifier.
# Integrity-checks the shipped fixtures, then EXECUTES the deliverable
# /app/token_service.py through the hidden flow harness: first against the
# shipped /app/config.json, then against generated hidden configs. The
# harness recomputes every expected HMAC and claim set itself, so nothing
# here encodes fixed outputs. Writes REWARD (0/1) to
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

log() { echo "tl-onyx-token verify: $*" >&2; }

# ---------------------------------------------------------------------------
# 1. The deliverable /app/token_service.py must exist.
# ---------------------------------------------------------------------------
if [ ! -f /app/token_service.py ]; then
  overall=0
  msgs="$msgs missing:token_service.py"
fi

# ---------------------------------------------------------------------------
# 2. Shipped fixtures must be byte-identical to pristine copies.
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  for pair in "config.json:/opt/pristine/config.json" \
              "lib/httpkit.py:/opt/pristine/httpkit.py"; do
    src="/app/${pair%%:*}"
    want="${pair##*:}"
    if [ ! -f "$src" ] || [ ! -f "$want" ] || ! cmp -s "$src" "$want"; then
      overall=0
      msgs="$msgs tampered:${src}"
    fi
  done
fi

# ---------------------------------------------------------------------------
# 3. Visible battery through the deliverable (restart propagation and
#    crafted-token matrix are inside the harness).
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  if [ -n "$TIMEOUT_CMD" ]; then
    $TIMEOUT_CMD 120 python3 /tests/hidden/flow_harness.py visible \
      >/tmp/to_visible.log 2>&1
  else
    python3 /tests/hidden/flow_harness.py visible >/tmp/to_visible.log 2>&1
  fi
  rc=$?
  if [ "$rc" -ne 0 ]; then
    overall=0
    msgs="$msgs visible-battery-failed"
    tail -40 /tmp/to_visible.log >&2 || true
  fi
fi

# ---------------------------------------------------------------------------
# 4. Hidden config batteries: three generated configurations (different
#    secrets, lifetimes, clock skew, users, ports) re-run through the same
#    flow battery by writing each to /app/config.json and restarting the
#    deliverable service.
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  if [ -n "$TIMEOUT_CMD" ]; then
    $TIMEOUT_CMD 150 python3 /tests/hidden/flow_harness.py hidden \
      >/tmp/to_hidden.log 2>&1
  else
    python3 /tests/hidden/flow_harness.py hidden >/tmp/to_hidden.log 2>&1
  fi
  rc=$?
  if [ "$rc" -ne 0 ]; then
    overall=0
    msgs="$msgs hidden-battery-failed"
    tail -40 /tmp/to_hidden.log >&2 || true
  fi
fi

if [ "$overall" = "1" ]; then
  log "all checks passed"
else
  log "FAIL${msgs:+:${msgs}}"
fi
finalize_reward
exit 0