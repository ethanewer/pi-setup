#!/bin/bash
# Verifier for item-005-hard.
set -u
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt

PMARS=/app/pmars
MINE=/app/tournament/mine.red

write_reward() { echo "$1" > /logs/verifier/reward.txt; }

if [ ! -x "$PMARS" ] || [ ! -f "$MINE" ]; then
  write_reward 0; exit 0
fi

# Sanity: /app/pmars must be the real pMARS binary.
if ! "$PMARS" -Zx 2>&1 | grep -qi 'unknown option'; then
  write_reward 0; exit 0
fi

# Immutability: the visible opponents must be untouched (byte-identical to the
# grading copies shipped with this task).
find /app/tournament/opponents -maxdepth 1 -name '*.red' -printf '%f\n' 2>/dev/null | sort > /tmp/vis.list
find /tests/opponents -maxdepth 1 -name '*.red' ! -name 'boss.red' -printf '%f\n' 2>/dev/null | sort > /tmp/grd.list
if ! cmp -s /tmp/vis.list /tmp/grd.list; then
  write_reward 0; exit 0
fi
tampered=0
for f in /tests/opponents/imp.red /tests/opponents/dwarf.red /tests/opponents/paper.red; do
  b=$(basename "$f")
  if ! cmp -s "$f" "/app/tournament/opponents/$b"; then
    tampered=1
  fi
done
if [ "$tampered" = "1" ]; then
  write_reward 0; exit 0
fi

# Hidden harness run against the grading opponent set (3 visible + held-back boss).
export OPP_DIR=/tests/opponents
OUT=$(cd /app/tournament && bash /tests/benchmark.sh "$MINE" 2>/dev/null)
points=$(echo "$OUT" | sed -n 's/.*points=\([0-9.]*\).*/\1/p' | head -1)
if [ -z "$points" ]; then
  write_reward 0; exit 0
fi

# Hard scoring map: 0.45 -> 0, 0.80 -> 1, linear in between.
reward=$(awk -v p="$points" 'BEGIN { if (p <= 0.45) r=0.0; else if (p >= 0.80) r=1.0; else r=(p-0.45)/0.35; if (r<0) r=0; if (r>1) r=1; printf "%.6f", r }' /dev/null)
write_reward "$reward"
exit 0