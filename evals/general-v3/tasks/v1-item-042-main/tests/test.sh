#!/bin/bash
# Verifier for item-042-main. Runs the agent's /app/vm.js against the sample
# AND against a hidden program assembled at verify time, comparing to fixed
# reference outputs. Always writes /logs/verifier/reward.txt (0..1).
set -uo pipefail

mkdir -p /logs/verifier
cd /app
F=/tests/fixtures
pass=0
total=5

if [ -f /app/vm.js ]; then
  # 1. sample trace
  if node /app/vm.js samples/sum10.elf --trace >/tmp/ag1 2>/dev/null && cmp -s /tmp/ag1 "$F/expected_sum10.trace"; then pass=$((pass+1)); fi
  # 2. sample snapshot
  if node /app/vm.js samples/sum10.elf --snapshot >/tmp/ag2 2>/dev/null && cmp -s /tmp/ag2 "$F/expected_sum10.snapshot.json"; then pass=$((pass+1)); fi
  # 3-5. hidden program (assembled here, invisible to the agent)
  if python3 tools/asm.py "$F/hidden_sum.s" -o /tmp/hidden.elf >/dev/null 2>&1; then
    if node /app/vm.js /tmp/hidden.elf --stdin "$F/in5.txt" --trace >/tmp/ag3 2>/dev/null && cmp -s /tmp/ag3 "$F/expected_hidden_sum.trace"; then pass=$((pass+1)); fi
    if node /app/vm.js /tmp/hidden.elf --stdin "$F/in5.txt" --snapshot >/tmp/ag4 2>/dev/null && cmp -s /tmp/ag4 "$F/expected_hidden_sum.snapshot.json"; then pass=$((pass+1)); fi
    node /app/vm.js /tmp/hidden.elf --stdin "$F/in5.txt" >/tmp/ag5 2>/dev/null
    rc=$?
    if [ "$rc" = "0" ] && cmp -s /tmp/ag5 "$F/expected_hidden_sum.out"; then pass=$((pass+1)); fi
  fi
fi

reward=$(python3 -c "print('%.2f' % ($pass/$total))")
echo "$reward" > /logs/verifier/reward.txt