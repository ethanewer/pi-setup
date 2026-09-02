#!/usr/bin/env bash
# Granite Grove verifier. Runs as root after the agent finishes.
# /tests and /solution are mounted read-only; the agent worked in /app.
#
# Executes the deliverable (pipeline program /app/solve.py) on the primary
# /app/data case AND on each hidden case, asserting:
#   * calendar files were freshly FETCHED from a live service (byte-equal to a
#     served copy carrying a per-process session id a static file cannot fake)
#   * the overlap finder was driven and its output equals the tool's own
#   * the transfer rule produces exactly the reference balances/owners/log
set -euo pipefail

REWARD_FILE=/logs/verifier/reward.txt
TOOLS=/app/tools
SOLVE=/app/solve.py
REF=/tests/ref_transfer.py

mkdir -p "$(dirname "$REWARD_FILE")"
fail() { echo "VERIFY-FAIL: $*" >&2; echo 0 > "$REWARD_FILE"; exit 1; }
okay() { echo "REWARD-OK: $*" >&2; echo 1 > "$REWARD_FILE"; exit 0; }

SVC_PID=""
start_service() { # cfg outdir outlog -> prints base url on success
  local cfg="$1" outdir="$2" out="$3" port=""
  rm -f "$out"
  python3 "$TOOLS/schedule_service.py" --config "$cfg" --port 0 \
      --outdir "$outdir" >"$out" 2>&1 &
  SVC_PID=$!
  for _ in $(seq 1 40); do
    if grep -q GRANITE_GROVE_UP "$out" 2>/dev/null; then
      port=$(grep -o 'port=[0-9]*' "$out" | head -1 | cut -d= -f2)
      break
    fi
    sleep 0.25
  done
  if [ -z "$port" ]; then return 1; fi
  echo "http://127.0.0.1:$port"
}
stop_service() {
  if [ -n "$SVC_PID" ]; then kill "$SVC_PID" 2>/dev/null || true; wait "$SVC_PID" 2>/dev/null || true; fi
  SVC_PID=""
}
trap 'kill "$SVC_PID" 2>/dev/null || true' EXIT

# Assert one case's outputs in $1 (case dir) against a live service
check_case() { # case served
  local case="$1" served="$2" out="$case/out"

  # (1) calendar: every person's saved .ics must byte-equal the live-served one
  python3 - "$case" "$served" "$out" <<'PY'
import json, os, sys
case, served, out = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = json.load(open(os.path.join(case, "calendar", "service_config.json")))
keys = [p["key"] for p in cfg["people"]]
assert keys, "service lists no people"
for key in keys:
    ref = os.path.join(served, key + ".ics")
    got = os.path.join(out, key + ".ics")
    rc1, rc2 = os.path.exists(ref), os.path.exists(got)
    assert rc1, "service never served " + key
    assert rc2, "pipeline never saved " + key
    assert open(ref, "rb").read() == open(got, "rb").read(), \
        "fetched calendar != live service for " + key
PY
  [ $? -eq 0 ] || fail "calendar fetch/freshness failed for $case"

  # (2) overlaps: pipeline output must equal the tool's own result on the CSV
  python3 "$TOOLS/find_overlaps.py" "$case/availability/availability.csv" \
      > /tmp/ref_overlaps.json
  python3 - "$out" <<'PY' || fail "overlap finder output mismatch for $case"
import json, os, sys
ref = json.load(open("/tmp/ref_overlaps.json"))
got = json.load(open(os.path.join(sys.argv[1], "overlaps.json")))
assert ref == got, "overlaps differ from tool output"
PY

  # (3) transfer: balances/ownership/log must match the reference rule
  python3 "$REF" "$case/ledger" > /tmp/ref_tfr.json
  python3 - "$out" <<'PY' || fail "transfer rule mismatch for $case"
import json, os, sys
ref = json.load(open("/tmp/ref_tfr.json"))
got = json.load(open(os.path.join(sys.argv[1], "transfer_out.json")))
assert ref == got, "transfer differs from reference"
PY
}

# Run the deliverable on a (copy of a) case and verify all three competencies.
# Hidden dirs are mounted read-only, so work on a writable copy.
run_verified_case() {
  local src="$1"
  local ws="/tmp/grove_work_${RANDOM}$$"; rm -rf "$ws"; mkdir -p "$ws"
  cp -r "$src"/* "$ws"/
  local case="$ws"
  local served="/tmp/served_${RANDOM}$$"; rm -rf "$served"; mkdir -p "$served"
  local slog="/tmp/svc_${RANDOM}.log"
  local url
  url=$(start_service "$case/calendar/service_config.json" "$served" "$slog") \
    || { rm -rf "$ws"; fail "could not start schedule service for $src"; }
  python3 "$SOLVE" --case "$case" --url "$url" \
    --out "$case/answer_local.json" >/tmp/solve_out.log 2>&1 \
    || { stop_service; rm -rf "$ws"
         fail "solve.py failed for $src: $(tail -3 /tmp/solve_out.log)"; }
  check_case "$case" "$served"; local rc=$?
  stop_service
  rm -rf "$ws"
  return $rc
}

# ---- primary ----------------------------------------------------------------
[ -f "$SOLVE" ] || fail "/app/solve.py missing"
python3 -c "import ast; ast.parse(open('/app/solve.py').read())" \
  || fail "/app/solve.py has a syntax error"

run_verified_case /app/data

# primary deliverable /app/answer.json well-formed & consistent
python3 - <<'PY' || fail "answer.json inconsistent for /app/data"
import json, os
p = "/app/answer.json"
assert os.path.exists(p), "missing /app/answer.json"
a = json.load(open(p))
assert a["pipeline"] == "granite-grove"
assert a["calendar"]["status"] == "ok"
assert a["calendar"]["files"] == ["mari.ics", "oden.ics"], a
PY

# ---- hidden cases -----------------------------------------------------------
[ -d /tests/hidden ] || fail "/tests/hidden missing"
count=0
for cdir in /tests/hidden/*; do
  [ -d "$cdir" ] || continue
  run_verified_case "$cdir"
  count=$((count + 1))
done
[ "$count" -ge 2 ] || fail "expected >=2 hidden cases, got $count"

okay "primary + $count hidden cases passed"