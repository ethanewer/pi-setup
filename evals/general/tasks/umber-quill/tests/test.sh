#!/bin/bash
set -uo pipefail
H=/tests/hidden
reward=1
fail() { echo "FAIL: $*"; reward=0; }
mkdir -p /logs/verifier

norm() { awk 'NF{w[n]=n$0; n++} END{for(i=0;i<n;i++) print w[i]}' "$1"; }

# ---- deliverable artifacts must exist ----
for x in /app/logproc.py /app/respond.py \
         /app/logs/round1.out /app/logs/round2.out /app/logs/round3.out \
         /app/logs/frames.json /app/logs/dates.tsv /app/incident.json; do
  [ -f "$x" ] || fail "missing deliverable $x"
done

# ---- 1) rounds partitioning on hidden events ----
T=$(mktemp -d)
rm -rf "$T"; mkdir -p "$T"
if python3 /app/logproc.py rounds "$H/events_hidden.ndjson" "$T" 2>/dev/null; then
  for r in 1 2 3; do
    if ! diff -u <(norm "$T/round$r.out") <(norm "$H/round$r.out.expected") >/dev/null 2>&1; then
      fail "hidden round$r mismatch"
    fi
  done
else
  fail "logproc rounds exited nonzero on hidden events"
fi
rm -rf "$T"

# ---- 2) frames parsing on hidden traces ----
if python3 /app/logproc.py frames "$H/traces_hidden.txt" /tmp/frames.json 2>/dev/null; then
  python3 - >/dev/null 2>&1 <<'PY' || fail "hidden frames mismatch"
import json,sys
exp=json.load(open("/tests/hidden/frames.expected"))
act=json.load(open("/tmp/frames.json"))
sys.exit(0 if exp==act else 1)
PY
else
  fail "frames exited nonzero"
fi

# ---- 3) last-date-on-IP-lines extraction on hidden lines ----
if python3 /app/logproc.py dates "$H/lines_hidden.txt" /tmp/dates.tsv 2>/dev/null; then
  if ! diff -u <(norm /tmp/dates.tsv) <(norm "$H/dates.expected") >/dev/null 2>&1; then
    fail "hidden dates mismatch"
  fi
else
  fail "dates cmd failed"
fi

# ---- 4) incident report on hidden activity (matching target) ----
if python3 /app/respond.py 10.9.9.7 "$H/activity_a.jsonl" "$H/activity_b.jsonl" /tmp/incident.json 2>/dev/null; then
  python3 - /tmp/incident.json <<'PY' || fail "hidden incident mismatch"
import json,sys
exp=json.load(open("/tests/hidden/incident.expected"))
try:
    act=json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if exp==act else 1)
PY
else
  fail "respond crashed on target ip"
fi

# ---- 5) incident report for an absent IP -> empty report ----
if python3 /app/respond.py 203.0.113.99 "$H/activity_a.jsonl" "$H/activity_b.jsonl" /tmp/empty.json 2>/dev/null; then
  python3 - /tmp/empty.json <<'PY' || fail "empty incident mismatch"
import json,sys
exp={"target_ip":"203.0.113.99","occurrences":0,"tokens":[],"start":None,"end":None}
try:
    act=json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if exp==act else 1)
PY
else
  fail "empty-target respond crashed"
fi

# ---- 6) invalid IPv4 inputs are rejected with non-zero exit + marker ----
for bad in 999.999.0.1 010.1.2.3 1.2.3 203.0.113; do
  out=$(python3 /app/respond.py "$bad" "$H/activity_a.jsonl" "$H/activity_b.jsonl" /tmp/x.json 2>/dev/null)
  code=$?
  if [ "$code" -eq 0 ]; then
    fail "invalid ip '$bad' accepted (exit 0)"
  fi
  case "$out" in
    *INVALID_IP*) ;;
    *) fail "invalid ip '$bad' missing INVALID_IP marker: $out" ;;
  esac
done

# ---- 7) deliverable files must match a fresh rerun over the fixtures ----
T=$(mktemp -d)
if python3 /app/logproc.py rounds /app/events.ndjson "$T" 2>/dev/null; then
  for r in 1 2 3; do
    if ! diff -u "$T/round$r.out" /app/logs/round$r.out >/dev/null 2>&1; then
      fail "round$r.out not reproduced faithfully"
    fi
  done
else
  fail "rerun of rounds on fixture crashed"
fi
rm -rf "$T"

if python3 /app/respond.py 203.0.113.55 /app/activity_a.jsonl /app/activity_b.jsonl /tmp/reinc.json 2>/dev/null; then
  python3 - <<'PY' || fail "incident.json not reproduced faithfully"
import json,sys
try:
    a=json.load(open("/tmp/reinc.json")); b=json.load(open("/app/incident.json"))
except Exception:
    sys.exit(1)
sys.exit(0 if a==b else 1)
PY
else
  fail "rerun respond crashed"
fi

echo "reward=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0