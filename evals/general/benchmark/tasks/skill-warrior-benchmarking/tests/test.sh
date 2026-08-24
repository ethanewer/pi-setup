#!/bin/bash

reward=0
if [ -f /app/benchmarking_answer.txt ]; then
  txt=$(tr '[:upper:]' '[:lower:]' < /app/benchmarking_answer.txt)
  has_repeat=$(grep -cE 'repeat|iterations?|multiple' <<<"$txt")
  has_summary=$(grep -cE 'mean|median|average' <<<"$txt")
  has_control=$(grep -cE 'control|reproduc|warmup|fixed' <<<"$txt")
  if [ "$has_repeat" -gt 0 ] && [ "$has_summary" -gt 0 ] && [ "$has_control" -gt 0 ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt