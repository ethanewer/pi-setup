#!/bin/bash
# Verifier for white-bell: executes /app/query.py on the visible inputs and on
# every hidden case under /tests/hidden, then writes the reward.
set -eu
mkdir -p /logs/verifier

compare() {
  python3 - "$1" "$2" <<'PY'
import json, sys

def canon(o):
    b = [dict(sorted(_.items())) for _ in o["bindings"]]
    b = sorted(b, key=lambda d: tuple(d[k] for k in sorted(d)))
    return (o.get("join_order"), b)

with open(sys.argv[1]) as f:
    got = json.load(f)
with open(sys.argv[2]) as f:
    want = json.load(f)
sys.exit(0 if canon(got) == canon(want) else 1)
PY
}

reward=0
visible_ok=0
hidden_ok=0
total=0

# 1) visible case: run the deliverable in /app where inputs live
if [ -f /app/query.py ]; then
  ( cd /app && python3 query.py ) 2>/dev/null || true
fi
if [ -f /app/query_result.json ] && compare /app/query_result.json /tests/expected.json; then
  visible_ok=1
fi

# 2) hidden cases in fresh scratch dirs
for dir in /tests/hidden/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  scratch=$(mktemp -d)
  cp "$dir/triples.json" "$dir/query.txt" "$scratch/"
  total=$((total + 1))
  ok=0
  if [ -f /app/query.py ] \
     && ( cd "$scratch" && python3 /app/query.py ) 2>/dev/null \
     && [ -f "$scratch/query_result.json" ] \
     && compare "$scratch/query_result.json" "$dir/expected"*.json; then
    ok=1
  fi
  if [ "$ok" -eq 1 ]; then hidden_ok=$((hidden_ok + 1)); fi
  rm -rf "$scratch"
done

if [ "$visible_ok" -eq 1 ] && [ "$total" -gt 0 ] && [ "$hidden_ok" -eq "$total" ]; then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0