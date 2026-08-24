#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/answer.tex" ]; then
  content=$(cat "$APP/answer.tex")
  ok=1
  for tok in "\\documentclass" "\\begin{document}" "\\end{document}" "\\frac"; do
    if ! printf '%s\n' "$content" | grep -Fq "$tok"; then ok=0; fi
  done
  if [ "$ok" = "1" ]; then reward=1; fi
fi
echo "$reward" > /logs/verifier/reward.txt