#!/bin/bash
# Verifier for item-005-main.
set -u
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt

PMARS=/app/pmars
MINE=/app/tournament/mine.red

write_reward() { echo "$1" > /logs/verifier/reward.txt; }

# Existence of required artifacts.
if [ ! -x "$PMARS" ] || [ ! -f "$MINE" ]; then
  write_reward 0; exit 0
fi

# Sanity: /app/pmars must really be the pMARS binary (reject fake scripts that
# would just print a high score).
if ! "$PMARS" -Zx 2>&1 | grep -qi 'unknown option'; then
  write_reward 0; exit 0
fi

# Run the hidden harness against the hidden opponent set.
export OPP_DIR=/tests/opponents
OUT=$(cd /app/tournament && bash /tests/benchmark.sh "$MINE" 2>/dev/null)
points=$(echo "$OUT" | sed -n 's/.*points=\([0-9.]*\).*/\1/p' | head -1)
if [ -z "$points" ]; then
  write_reward 0; exit 0
fi

# Map points to reward: 0,30 -> 0, 0.75+ -> 1, linear between.
reward=$(awk -v p="$points" 'BEGIN { if (p <= 0.30) r=0.0; else if (p >= 0.75) r=1.0; else r=(p-0.30)/0.45; if (r<0) r=0; if (r>1) r=1; printf "%.6f", r }' /dev/null)
write_reward "$reward"
exit 0