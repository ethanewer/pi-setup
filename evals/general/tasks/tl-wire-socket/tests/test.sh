#!/bin/bash
#
# tl-wire-socket verifier.
# Executes the deliverable /app/ws_server.py (via `python3 /app/ws_server.py`),
# which must read /app/config.json at startup and serve the documented
# WebSocket subset. Checks the shipped socket skeleton /app/lib/sockkit.py is
# still byte-identical, then runs the raw-socket probe on the visible config
# and on every hidden config in /tests/hidden/configs (different ports/paths,
# so hardcoding the visible values fails). Writes reward.txt via EXIT trap.
set -u
mkdir -p /logs/verifier

TIMEOUT_CMD=$(command -v timeout || true)
[ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""

PROBE=/tests/hidden/probe_ws.py
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

log() { echo "tl-wire-socket verify: $*" >&2; }

# ---------------------------------------------------------------------------
# 1. Static checks: deliverable present, sockkit untouched.
# ---------------------------------------------------------------------------
if [ ! -f /app/ws_server.py ]; then
  overall=0; msgs="$msgs missing:ws_server.py"
fi
if [ ! -f /app/config.json ]; then
  overall=0; msgs="$msgs missing:config.json"
fi
if [ -f /app/lib/sockkit.py ] && cmp -s /app/lib/sockkit.py /opt/pristine/sockkit.py; then
  :
else
  overall=0; msgs="$msgs sockkit:missing-or-modified"
fi
[ -f "$PROBE" ] || { overall=0; msgs="$msgs missing:probe_ws.py"; }

# ---------------------------------------------------------------------------
# run_one <config.json> <label>: start the deliverable with that config,
# wait for the port to accept a TCP connection, run the probe, kill server.
# ---------------------------------------------------------------------------
run_one() {
  local cfg="$1" label="$2"
  local srv port ok=0 rc=1 i
  if [ "$cfg" != "/app/config.json" ]; then
    cp "$cfg" /app/config.json || { msgs="$msgs $label:config-copy"; return 1; }
  fi
  port=$(python3 -c "import json,sys;print(json.load(open('$cfg'))['port'])" 2>/dev/null) || {
    msgs="$msgs $label:bad-config"; return 1; }
  $TIMEOUT_CMD 90 python3 /app/ws_server.py >"/tmp/ws_${label}.log" 2>&1 &
  srv=$!
  for i in $(seq 1 60); do
    # shell /dev/tcp connect; server handler sees a bare connect and must
    # close it quietly (documented behavior).
    if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
      # subshell's fd 3 closes with the subshell; nothing to clean up here
      ok=1
      break
    fi
    if ! kill -0 "$srv" 2>/dev/null; then break; fi
    sleep 0.1
  done
  if [ "$ok" = "1" ]; then
    if $TIMEOUT_CMD 120 python3 "$PROBE" "$cfg" >"/tmp/ws_probe_${label}.log" 2>&1; then
      rc=0
    fi
  else
    log "server '$label' never listened"
    tail -5 "/tmp/ws_${label}.log" >&2 2>/dev/null || true
  fi
  kill "$srv" 2>/dev/null
  wait "$srv" 2>/dev/null
  return $rc
}

# ---------------------------------------------------------------------------
# 2. Execute the deliverable: visible config, then each hidden config.
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  if ! run_one /app/config.json visible; then
    overall=0; msgs="$msgs visible-probe-failed"
    tail -20 /tmp/ws_probe_visible.log >&2 2>/dev/null || true
  fi
fi

if [ "$overall" = "1" ]; then
  n=0
  for cfg in /tests/hidden/configs/*.json; do
    [ -f "$cfg" ] || continue
    n=$((n + 1))
    label=$(basename "$cfg" .json)
    if ! run_one "$cfg" "$label"; then
      overall=0
      msgs="$msgs hidden-probe-failed:$label"
      tail -20 "/tmp/ws_probe_${label}.log" >&2 2>/dev/null || true
    fi
  done
  [ "$n" -ge 3 ] || { overall=0; msgs="$msgs too-few-hidden-configs:$n"; }
fi

if [ "$overall" = "1" ]; then
  log "all checks passed"
else
  log "FAIL${msgs:+:${msgs}}"
fi
finalize_reward
exit 0