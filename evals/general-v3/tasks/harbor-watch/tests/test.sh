#!/bin/bash
# Harbor Watch verifier. Runs as root after the agent finishes.
# /tests and /solution are mounted read-only; the agent worked in /app.
#
# Executes the deliverable (/app/solve.py) on the primary /app/data case AND on
# each hidden case, asserting:
#   * each crew member's saved .ics was freshly FETCHED from a live roster
#     service (byte-equal to a served copy carrying a per-process session id a
#     static file cannot fake) via bearer-token auth
#   * the summary JSON equals an exact reference computed from the served bytes
set -euo pipefail

REWARD_FILE=/logs/verifier/reward.txt
SOLVE=/app/solve.py

mkdir -p "$(dirname "$REWARD_FILE")"
fail() { echo "VERIFY-FAIL: $*" >&2; echo 0 > "$REWARD_FILE"; exit 1; }
okay() { echo "REWARD-OK: $*" >&2; echo 1 > "$REWARD_FILE"; exit 0; }

SVC_PID=""
start_service() { # cfg outdir outlog -> prints base url on success
  local cfg="$1" outdir="$2" out="$3" port=""
  rm -f "$out"
  python3 /app/tools/roster_service.py --config "$cfg" --port 0 \
      --outdir "$outdir" >"$out" 2>&1 &
  SVC_PID=$!
  for _ in $(seq 1 40); do
    if grep -q HARBOR_WATCH_UP "$out" 2>/dev/null; then
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

# Reference summary recomputed deterministically from the case config (same
# calendar semantics as the roster service, independent of any live service).
reference_summary() { # case_dir -> prints JSON on stdout
  python3 - "$1" <<'PY'
import json, os, sys

case = sys.argv[1]
DOW_MIN = 1440
DOW = {"Mon": 0, "Tue": 1, "Wed": 2, "Thu": 3, "Fri": 4, "Sat": 5, "Sun": 6}

def minutes(t):
    return int(t[0:8]) * DOW_MIN + int(t[9:11]) * 60 + int(t[11:13])

def parse_ics(text):
    events = []
    for block in re.findall(r"BEGIN:VEVENT\r?\n(.*?)END:VEVENT", text, re.S):
        ms = re.search(r"DTSTART:(\d{8}T\d{6})", block)
        me = re.search(r"DTEND:(\d{8}T\d{6})", block)
        if not (ms and me):
            continue
        events.append((ms.group(1), me.group(1)))
    return events

cfg = json.load(open(os.path.join(case, "roster", "service_config.json")))
keys = [p["key"] for p in cfg["crew"]]
assert len(keys) >= 1, "no crew listed"
base = int(cfg["base_date"])
parsed = {}
for person in cfg["crew"]:
    evs = []
    for w in person.get("watches", []):
        day = base + DOW.get(w["day"], 0)
        evs.append(("%dT%s00" % (day, w["start"].replace(":", "")),
                    "%dT%s00" % (day, w["end"].replace(":", ""))))
    parsed[person["key"]] = evs

calendars = {}
for k in keys:
    evs = parsed[k]
    calendars[k] = {
        "events": len(evs),
        "first_start": min(s for s, _ in evs) if evs else None,
        "last_end": max(e for _, e in evs) if evs else None,
        "busy_minutes": sum(minutes(e) - minutes(s) for s, e in evs),
    }
overlap = 0
for i in range(len(keys)):
    for j in range(i + 1, len(keys)):
        for s1, e1 in parsed[keys[i]]:
            for s2, e2 in parsed[keys[j]]:
                inter = min(minutes(e1), minutes(e2)) - max(minutes(s1), minutes(s2))
                if inter > 0:
                    overlap += inter
ref = {
    "task": "harbor-watch",
    "terminal": cfg["terminal"],
    "crew": keys,
    "calendars": calendars,
    "overlap_minutes": overlap,
}
print(json.dumps(ref))
PY
}

# Assert one case: byte-fresh calendars + exact reference summary.
check_case() { # case served out_dir result_json
  local case="$1" served="$2" out="$3" result="$4"
  python3 - "$case" "$served" "$out" <<'PY'
import json, os, sys
case, served, out = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = json.load(open(os.path.join(case, "roster", "service_config.json")))
keys = [p["key"] for p in cfg["crew"]]
for key in keys:
    ref = os.path.join(served, key + ".ics")
    got = os.path.join(out, key + ".ics")
    assert os.path.exists(ref), "service never served " + key
    assert os.path.exists(got), "pipeline never saved " + key
    assert open(ref, "rb").read() == open(got, "rb").read(), \
        "fetched calendar != live service for " + key
PY
  [ $? -eq 0 ] || return 1

  local ref_json
  ref_json=$(reference_summary "$case") || return 1
  python3 - "$result" "$ref_json" <<'PY'
import json, os, sys
result_path, ref_json = sys.argv[1], sys.argv[2]
assert os.path.isfile(result_path), "missing summary " + result_path
got = json.load(open(result_path))
ref = json.loads(ref_json)
assert got == ref, "summary mismatch:\n got=%r\n ref=%r" % (got, ref)
PY
  [ $? -eq 0 ]
}

run_verified_case() { # src_case_dir
  local src="$1"
  local ws="/tmp/watch_work_${RANDOM}$$"; rm -rf "$ws"; mkdir -p "$ws"
  cp -r "$src"/* "$ws"/
  local case="$ws"
  local served="/tmp/watch_served_${RANDOM}$$"; rm -rf "$served"; mkdir -p "$served"
  local slog="/tmp/watch_svc_${RANDOM}.log"
  local url
  url=$(start_service "$case/roster/service_config.json" "$served" "$slog") \
    || { rm -rf "$ws"; fail "could not start roster service for $src"; }
  python3 "$SOLVE" --case "$case" --url "$url" \
    --out "$case/summary_local.json" >/tmp/watch_solve.log 2>&1 \
    || { stop_service; rm -rf "$ws"
         fail "solve.py failed for $src: $(tail -3 /tmp/watch_solve.log)"; }
  check_case "$case" "$served" "$case/out" "$case/summary_local.json"
  local rc=$?
  stop_service
  rm -rf "$ws"
  return $rc
}

# ---- primary ----------------------------------------------------------------
[ -f "$SOLVE" ] || fail "/app/solve.py missing"
python3 -c "import ast; ast.parse(open('/app/solve.py').read())" \
  || fail "/app/solve.py has a syntax error"
[ -f /app/tools/roster_service.py ] || fail "/app/tools/roster_service.py missing"

run_verified_case /app/data || fail "primary case failed"

# primary deliverable /app/answer.json: compare against the deterministic
# reference for /app/data (summary is service-session-independent).
pref=$(reference_summary /app/data)
python3 - "$pref" <<'PY' || fail "primary /app/answer.json inconsistent"
import json, os, sys
assert os.path.isfile("/app/answer.json"), "missing /app/answer.json"
got = json.load(open("/app/answer.json"))
ref = json.loads(sys.argv[1])
assert got == ref, "answer.json mismatch:\n got=%r\n ref=%r" % (got, ref)
PY

# ---- hidden cases -----------------------------------------------------------
[ -d /tests/hidden ] || fail "/tests/hidden missing"
count=0
for cdir in /tests/hidden/*; do
  [ -d "$cdir" ] || continue
  run_verified_case "$cdir" || fail "hidden case $cdir failed"
  count=$((count + 1))
done
[ "$count" -ge 2 ] || fail "expected >=2 hidden cases, got $count"

okay "primary + $count hidden cases passed"