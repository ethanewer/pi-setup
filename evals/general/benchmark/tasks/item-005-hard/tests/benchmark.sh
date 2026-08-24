#!/bin/bash
# benchmark.sh <mine.red>
# Runs the submitted Redcode warrior against every opponent in the opponents
# directory with a fixed deterministic Core War session and reports the
# aggregate "points" metric (see metric note in INSTALL.md).
set -u

PMARS=/app/pmars
ROUNDS=60
CORESIZE=8000
CYCLES=80000
OPP_DIR=${OPP_DIR:-/app/tournament/opponents}

if [ ! -f "$PMARS" ]; then
  echo "pmars binary not found at $PMARS (build pMARS first)."
  exit 2
fi
if [ $# -lt 1 ] || [ ! -f "$1" ]; then
  echo "usage: $0 MINE.red"
  exit 2
fi

wins=0; draws=0; games=0; opps=0
for opp in "$OPP_DIR"/*.red; do
  [ -f "$opp" ] || continue
  opps=$((opps + 1))
  out=$("$PMARS" -b -k -r "$ROUNDS" -c "$CYCLES" -s "$CORESIZE" -f "$1" "$opp" 2>/dev/null)
  lines=$(echo "$out" | tail -2)
  w=$(echo "$lines" | sed -n '1p' | awk '{print $1}')
  d=$(echo "$lines" | sed -n '1p' | awk '{print $2}')
  wins=$((wins + (w > 0 ? w : 0)))
  draws=$((draws + (d > 0 ? d : 0)))
  games=$((games + ROUNDS))
done

if [ "$opps" -eq 0 ]; then
  echo "no opponents found in $OPP_DIR"
  exit 2
fi

points=$(awk -v W="$wins" -v D="$draws" -v G="$games" 'BEGIN { printf "%.6f", (W + 0.5*D)/G }')
echo "opps=$opps rounds=$ROUNDS games=$games wins=$wins draws=$draws points=$points"