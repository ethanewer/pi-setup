#!/usr/bin/env bash
# Drift Pier verifier. Runs as root after the agent finishes.
# /tests and /solution are mounted read-only; the agent worked in /app.
#
# Executes the deliverable pipeline /app/clean.py on the shipped /app/data
# baseline AND on every hidden input directory, asserting each recomputed
# output (aggregations + boolean columns, the transfer rule state, the
# interpolated tide table, the top-k url ranking, and the iCal blocking
# intervals) matches the independent reference /tests/check.py.
set -euo pipefail

REWARD_FILE=/logs/verifier/reward.txt
SOLVE=/app/clean.py
REF=/tests/check.py

mkdir -p "$(dirname "$REWARD_FILE")"
fail() { echo "VERIFY-FAIL: $*" >&2; echo 0 > "$REWARD_FILE"; exit 1; }
okay() { echo "REWARD-OK: $*" >&2; echo 1 > "$REWARD_FILE"; exit 0; }

# ---- deliverable presence & sanity -----------------------------------------
[ -f "$SOLVE" ] || fail "/app/clean.py missing"
python3 -c "import ast; ast.parse(open('$SOLVE').read())" \
  || fail "/app/clean.py has a syntax error"
[ -f /app/result.json ] || fail "deliverable /app/result.json missing"
[ -s /app/top.tsv ] || fail "deliverable /app/top.tsv missing or empty"
python3 -c "import json; json.load(open('/app/result.json'))" \
  || fail "/app/result.json is not valid JSON"

# ---- primary baseline ------------------------------------------------------
[ -d /app/data ] || fail "/app/data missing"
rm -rf /tmp/pier_primary
python3 "$SOLVE" /app/data /tmp/pier_primary >/dev/null 2>&1 \
  || fail "clean.py failed on /app/data"
python3 "$REF" /app/data /tmp/pier_primary > /tmp/pier_check.log 2>&1 \
  || fail "primary /app/data mismatch: $(head -3 /tmp/pier_check.log)"

# ---- hidden cases -----------------------------------------------------------
[ -d /tests/hidden ] || fail "/tests/hidden missing"
count=0
for cdir in /tests/hidden/*; do
  [ -d "$cdir" ] || continue
  for k in ledger.json transfers.csv metrics.csv tide.csv surge.tsv; do
    [ -f "$cdir/$k" ] || fail "hidden case $cdir missing $k"
  done
  mkdir -p /tmp/pier_out_$count
  python3 "$SOLVE" "$cdir" /tmp/pier_hidden_$count >/tmp/pier_solve.log 2>&1 \
    || fail "clean.py failed on $cdir: $(tail -3 /tmp/pier_solve.log)"
  python3 "$REF" "$cdir" /tmp/pier_hidden_$count > /tmp/pier_check.log 2>&1 \
    || fail "$(basename $cdir) mismatch: $(head -3 /tmp/pier_check.log)"
  count=$((count + 1))
done
[ "$count" -ge 2 ] || fail "expected >=2 hidden cases, got $count"

okay "primary + $count hidden cases passed"