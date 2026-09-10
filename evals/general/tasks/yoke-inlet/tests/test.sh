#!/usr/bin/env bash
# Verifier for yoke-inlet (nginx reverse-proxy stack: TLS, canary split,
# health-based failover, custom access-log format).
#
# Drives the agent's stack three times (visible routes + two hidden route sets):
#   per case - start the stack via /app/start.sh, poll https:/healthz, make real
#   HTTPS calls using the agent's /app/tls/ca.crt (verification fully on), check
#   the 300-request canary split band, parse the YOKE access-log format on every
#   route of the case, kill one upstream, assert 30 requests all succeed from
#   the surviving upstream, assert those land in the log too.
set -u
mkdir -p /logs/verifier
FAILED=0
work=$(mktemp -d)
trap 'rm -rf "$work"; [ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
fail() { echo "FAIL: $*" >&2; FAILED=1; }

PROBE=/tests/helpers/probe.py
CA=/app/tls/ca.crt
HOST=127.0.0.1
FRONT_PORT=8443
CANARY_PORT=8123
STABLE_PORT=8124
ACCESS_LOG=/app/logs/access.log
ERROR_LOG=/app/logs/error.log

echo "yoke-inlet verifier runs as $(id -un) (uid $(id -u))" >&2

# ---------------------------------------------------------------------------
# deliverable presence (this is the fast path that must fail if nothing ran)
# ---------------------------------------------------------------------------
for d in /app/start.sh /app/nginx.conf /app/tls/ca.crt; do
  if [ -f "$d" ]; then :; else fail "deliverable missing: $d"; fi
done
if [ "$FAILED" = 1 ]; then
  echo "reward=0 (missing deliverables)" >&2
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

# static sanity of the delivered nginx config
if ! nginx -t -c /app/nginx.conf >"$work/nginx-t.out" 2>&1; then
  fail "nginx -t rejects /app/nginx.conf: $(tail -3 "$work/nginx-t.out")"
fi

# ---------------------------------------------------------------------------
# stack lifecycle helpers
# ---------------------------------------------------------------------------
stop_stack() {
  pkill -x nginx 2>/dev/null || true
  pkill -f '[u]pstreams/app_server.py' 2>/dev/null || true
  python3 "$PROBE" stop 2>/dev/null || true
  sleep 0.2
}

start_stack() {
  stop_stack
  : > "$ACCESS_LOG" 2>/dev/null || true
  rm -f /app/run/nginx.pid 2>/dev/null || true
  if ! timeout 120 bash /app/start.sh >"$work/start.out" 2>&1; then
    echo "  start.sh rc=$?; output:" >&2
    sed 's/^/    start| /' "$work/start.out" | tail -8 >&2
    if [ -f "$ERROR_LOG" ]; then
      echo "  nginx error log tail:" >&2
      tail -15 "$ERROR_LOG" | sed 's/^/    errlog| /' >&2
    fi
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# one full case: TLS + split + log format + failover + failover log format
# ---------------------------------------------------------------------------
run_case() { # $1 label  $2 routes (space separated)  $3 kill target (canary|stable)
  local label="$1" routes="$2" kill_target="$3"
  local sfx survivor kill_port_num
  sfx=$(printf '%s' "$label" | tr 'A-Z' 'a-z')
  if [ "$kill_target" = "canary" ]; then
    survivor=stable; kill_port_num=$CANARY_PORT
  else
    survivor=canary; kill_port_num=$STABLE_PORT
  fi
  echo "== case $label (routes: $routes, kill: $kill_target => survivor: $survivor) ==" >&2

  if ! start_stack; then
    fail "$label: /app/start.sh did not bring the stack up"
    return
  fi

  if ! python3 "$PROBE" wait-ready "$CA" "$HOST" "$FRONT_PORT" 60 "$sfx"; then
    fail "$label: front door never answered /healthz over TLS"
    return
  fi

  # real HTTPS with the delivered CA bundle; verification is never disabled
  code=$(curl -sS --cacert "$CA" --max-time 15 -o "$work/hz.json" -w '%{http_code}' \
        "https://$HOST:$FRONT_PORT/healthz" 2>"$work/hz.err")
  if [ "$code" != "200" ]; then
    fail "$label: curl --cacert over https returned HTTP $code ($(head -1 "$work/hz.err"))"
  else
    hzok=$(python3 - "$work/hz.json" <<'PY' 2>/dev/null || true
import json,sys
d=json.load(open(sys.argv[1]))
assert d.get("status")=="ok" and d.get("server") in ("canary","stable")
print("ok")
PY
)
    [ "$hzok" = "ok" ] || fail "$label: /healthz body is not the upstream health JSON"
  fi

  if ! python3 "$PROBE" split "$CA" "$HOST" "$FRONT_PORT" "yoke-split-$sfx" $routes; then
    fail "$label: canary split outside the 60-72% band over 300 requests"
  fi

  if ! python3 "$PROBE" logcheck "$CA" "$HOST" "$FRONT_PORT" "$ACCESS_LOG" \
       "yoke-split-$sfx" 300 $routes; then
    fail "$label: access log lacks a compliant YOKE record for a case route"
  fi

  # --- failover ---
  if ! python3 "$PROBE" killport "$kill_port_num"; then
    fail "$label: could not stop the $kill_target upstream (port $kill_port_num)"
    return
  fi
  sleep 0.3
  if ! python3 "$PROBE" failover "$CA" "$HOST" "$FRONT_PORT" "yoke-fail-$sfx" "$survivor" $routes; then
    fail "$label: after killing $kill_target, not all requests were served by $survivor"
  fi
  if ! python3 "$PROBE" logcheck "$CA" "$HOST" "$FRONT_PORT" "$ACCESS_LOG" \
       "yoke-fail-$sfx" 30 $routes; then
    fail "$label: failover requests not recorded in the YOKE format"
  fi
  echo "== case $label DONE ==" >&2
}

# ---------------------------------------------------------------------------
# visible case
# ---------------------------------------------------------------------------
run_case VISIBLE "/mortar /trestle" stable

# ---------------------------------------------------------------------------
# hidden cases
# ---------------------------------------------------------------------------
for manifest in /tests/hidden/*/case.json; do
  [ -f "$manifest" ] || continue
  routes=$(python3 - "$manifest" <<'PY' || true
import json, sys
print(" ".join(json.load(open(sys.argv[1]))["routes"]))
PY
)
  killt=$(python3 - "$manifest" <<'PY' || true
import json, sys
print(json.load(open(sys.argv[1]))["kill"])
PY
)
  if [ -z "$routes" ] || [ -z "$killt" ]; then
    fail "hidden case manifest unreadable: $manifest"
    continue
  fi
  run_case "$(basename "$(dirname "$manifest")")" "$routes" "$killt"
done

# ---------------------------------------------------------------------------
if [ "$FAILED" = 0 ]; then
  reward=1
else
  echo "--- diagnostics: nginx error log tail ---" >&2
  tail -25 "$ERROR_LOG" 2>/dev/null | sed 's/^/    err| /' >&2 || true
  reward=0
fi
echo "yoke-inlet verifier: reward=$reward" >&2
echo "$reward" > /logs/verifier/reward.txt
exit 0