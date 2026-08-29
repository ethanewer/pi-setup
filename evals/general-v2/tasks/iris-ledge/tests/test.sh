#!/bin/bash
# iris-ledge verifier (tests/test.sh).
#
# Re-executes the deliverable /app/run.sh on the main scenario and on every
# hidden scenario in /tests/hidden, validates OUTDIR/result.json + the rendered
# PPM frame with tests/validate.py, and independently probes the background
# emulator's monitor console and serial redirect to confirm the guest is alive
# as a persistent service.
#
# Always ends by writing a numeric reward to /logs/verifier/reward.txt.
set -u

fail() { echo 0 > /logs/verifier/reward.txt; echo "VERIFIER FAIL: $1"; exit 0; }

[ -x /app/run.sh ] || fail "no /app/run.sh (pristine container)"
MAIN="/app/scenario-main.json"
[ -f "$MAIN" ] || MAIN=$(ls /app/scenario-main.json 2>/dev/null || true)
[ -z "$MAIN" ] && MAIN=/app/scenario-main.json
[ -f "$MAIN" ] || fail "no main scenario file"

get() { python3 -c "import json,sys;print(json.load(open('$1')).get('$2',''))"; }

# Independent socket checks proving the emulator is alive in the background.
check_monitor() {
  local port="$1"
  timeout 6 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port; printf 'info cpus\n' >&3; (timeout 3 dd bs=1 count=400 <&3 2>/dev/null)" 2>/dev/null \
    | grep -qiE 'qemu|cpu#' && return 0 || return 1
}
check_serial() {
  local port="$1"
  timeout 10 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port; sleep 1; printf 'echo IRIS_VRFY_OK\\n' >&3; (timeout 6 dd bs=1 count=16384 <&3 2>/dev/null)" 2>/dev/null \
    | grep -q IRIS_VRFY_OK && return 0 || return 1
}

run_and_check() {
  local scn="$1" out="$2"
  bash /app/run.sh "$scn" "$out" || fail "run.sh returned nonzero for $scn"
  python3 /tests/validate.py "$out" "$scn" || fail "validation for $scn"
  local mp sp
  mp=$(get "$scn" monitor_port); sp=$(get "$scn" serial_port)
  check_monitor "$mp" || fail "monitor socket dead for $scn (port $mp)"
  check_serial "$sp" || fail "serial socket dead for $scn (port $sp)"
}

# 1) main scenario -> /app
run_and_check "$MAIN" "/app"
# The main scenario must produce the declared deliverable /app/result.json.
[ -f /app/result.json ] || fail "no /app/result.json after main scenario run"
python3 /tests/validate.py /app "$MAIN" || fail "re-validation of /app/result.json"

# 2) hidden scenarios -> per-case outdirs
i=0
for scn in /tests/hidden/*.json; do
  i=$((i + 1))
  out="/tmp/iris_out_h$i"
  mkdir -p "$out"
  run_and_check "$scn" "$out"
done
[ "$i" -ge 2 ] || fail "expected at least 2 hidden scenarios, got $i"

echo 1 > /logs/verifier/reward.txt
echo "VERIFIER PASS: main + $i hidden scenarios"
