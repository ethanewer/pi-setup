#!/usr/bin/env bash
mkdir -p /logs/verifier

reward=0
if [ -f /app/stats.cpp ]; then
  if g++ -O2 -o /tmp/stats /app/stats.cpp 2>/tmp/gxx.log; then
    got=$(/tmp/stats < /app/data.txt)
    exp_sum=$(awk '{s+=$1} END{print s}' /app/data.txt)
    exp_cnt=$(wc -l < /app/data.txt)
    exp_avg=$(awk '{s+=$1} END{printf "%.1f", s/NR}' /app/data.txt)
    want=$(printf 'sum=%s\ncount=%s\navg=%s' "$exp_sum" "$exp_cnt" "$exp_avg")
    if [ "$got" = "$want" ]; then
      reward=1
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt