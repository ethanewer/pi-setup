#!/usr/bin/env bash
# Verifier for basalt-vault. Executes the /app/grid.py deliverable against the
# visible maze (fresh server on a fresh port) and against every hidden maze
# fixture, validating the live game state and the produced /app/map.txt each
# time. Writes 0/1 to /logs/verifier/reward.txt.
set -uo pipefail

LOGS=/logs/verifier
mkdir -p "$LOGS"
reward=0
reason=""
echo "[verifier] starting"

if [ ! -f /app/grid.py ]; then
  echo "[verifier] FAIL: /app/grid.py missing" >&2
  echo "0" > "$LOGS/reward.txt"
  exit 0
fi

# ---- visible case: maze-0 from the shipped fixture ------------------------
PORT=8200
rm -f /tmp/map_visible.txt
if ! python3 /tests/check.py --fixture /app/vault_fixtures.json --maze maze-0 \
     --port $PORT --out /tmp/map_visible.txt; then
  echo "[verifier] FAIL: visible maze-0" >&2
  echo "0" > "$LOGS/reward.txt"
  exit 0
fi

# ---- hidden cases --------------------------------------------------------
cases=( "case1:isthmus-8:8201"
        "case2:corridor-2:8202"
        "case3:strand-4:8203" )

all_pass=1
for entry in "${cases[@]}"; do
  dir="${entry%%:*}"
  rest="${entry#*:}"
  maze="${rest%%:*}"
  port="${rest##*:}"
  rm -f /tmp/map_hidden.txt
  if ! python3 /tests/check.py --fixture "/tests/hidden/$dir/vault.json" \
       --maze "$maze" --port "$port" --out /tmp/map_hidden.txt; then
    echo "[verifier] FAIL: hidden $dir ($maze)" >&2
    all_pass=0
    break
  fi
done

if [ "$all_pass" -eq 1 ]; then
  reward=1
  reason="visible + ${#cases[@]} hidden cases passed"
fi
echo "[verifier] result: REWARD=$reward ($reason)"
echo "$reward" > "$LOGS/reward.txt"
exit 0