#!/usr/bin/env bash
# Verifier for cypress-lantern: starts the shipped beacon service, re-runs the
# /app deliverables against it (visible delta-7 case plus every hidden case in
# /tests/hidden), and checks real HTTP behaviour including negative cases.
# Always writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0
PASS=1
fail() { echo "FAIL: $*"; PASS=0; }
BASE="http://127.0.0.1:8917"
APP_PID=""

# Reuse the service if an agent already has it up; otherwise start it.
if ! curl -sf "$BASE/api/announce" -o /dev/null 2>/dev/null; then
  (cd /app && python3 -m lantern_service.app >/tmp/lantern.log 2>&1) &
  APP_PID=$!
  trap 'kill "$APP_PID" 2>/dev/null' EXIT TERM INT
  up=0
  for i in $(seq 1 60); do
    if curl -sf "$BASE/api/announce" -o /dev/null 2>/dev/null; then up=1; break; fi
    sleep 0.25
  done
  if [ "$up" != "1" ]; then
    echo "FAIL: beacon service would not start"; echo 0 > /logs/verifier/reward.txt; exit 0
  fi
fi

# ---- 0. deliverables exist ----
for f in light_beacon.py final_message.txt; do
  if [ ! -f "/app/$f" ]; then fail "missing deliverable /app/$f"; fi
done

# ---- 1. the service actually gates the payload (negative control) ------------
bad_code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  -H 'Content-Type: application/json' \
  -d '{"turn":"00000000","key":"deadbeefdeadbeef"}' \
  "$BASE/api/beacon/delta-7/light")
if [ "$bad_code" = "200" ]; then fail "service accepted a bogus payload"; fi
unk_code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/beacon/ghost-99/challenge")
if [ "$unk_code" != "404" ]; then fail "unknown beacon not answered 404 (got $unk_code)"; fi

# ---- 2. expected-final computation (same formulas as the shipped service) ----
expect_final() {
  python3 - "$1" <<'PY'
import hashlib, sys
b = sys.argv[1]
ch = hashlib.sha256(("waxis:" + b).encode()).hexdigest()[:24]
turn = hashlib.sha256(("rotor:" + ch).encode()).hexdigest()[:8]
key = hashlib.sha256(("filament:" + turn).encode()).hexdigest()[:16]
print("lamplit-" + hashlib.sha256(("beam:" + key).encode()).hexdigest()[:8])
PY
}

run_success() {
  want=$(expect_final "$1")
  out=$(python3 /app/light_beacon.py "$1" 2>/tmp/lb.err)
  rc=$?
  if [ "$rc" -ne 0 ]; then fail "light_beacon($1): exited $rc"; sed 's/^/    /' /tmp/lb.err | head -3; return; fi
  if [ "$out" != "$want" ]; then fail "light_beacon($1): got '${out:-}' want '$want'"; fi
}

run_negative() {
  out=$(python3 /app/light_beacon.py "$1" 2>/tmp/lb.err)
  rc=$?
  if [ "$rc" -eq 0 ]; then fail "light_beacon('$1'): should exit non-zero"; fi
  if printf '%s' "$out" | grep -q "lamplit-"; then fail "light_beacon('$1'): printed a final string on failure"; fi
  if [ ! -s /tmp/lb.err ]; then fail "light_beacon('$1'): no diagnostic on stderr"; fi
}

# ---- 3. visible case: default beacon delta-7 ---------------------------------
if [ -f /app/light_beacon.py ]; then
  run_success "delta-7"
  want=$(expect_final "delta-7")
  if [ -f /app/final_message.txt ]; then
    got="$(tr -d ' \t\r\n' < /app/final_message.txt)"
    if [ "$got" != "$want" ]; then
      fail "final_message.txt holds '$got' want '$want'"
    fi
  fi
fi

# ---- 4. hidden cases ----------------------------------------------------------
for dir in /tests/hidden/*/; do
  [ -d "$dir" ] || continue
  mode=$(cat "$dir/mode" 2>/dev/null)
  arg=$(cat "$dir/arg" 2>/dev/null)
  if [ "$mode" = "success" ]; then
    run_success "$arg"
  elif [ "$mode" = "fail" ]; then
    run_negative "$arg"
  else
    fail "hidden $dir: invalid mode '${mode:-}'"
  fi
done

# ---- reward -------------------------------------------------------------------
[ "$PASS" -eq 1 ] && reward=1
if [ "$reward" -eq 1 ]; then echo REWARD=1; else echo REWARD=0; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
