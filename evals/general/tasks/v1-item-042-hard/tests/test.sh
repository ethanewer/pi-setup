#!/bin/bash
# Verifier for item-042-hard. Runs the agent's /app/vm.js on the shipped
# samples (recursive factorial + segv trap) and on hidden programs it
# assembles itself (factorial with stdin inputs 6 and 9). Compares to fixed
# reference outputs. Always writes /logs/verifier/reward.txt (0..1).
set -uo pipefail

mkdir -p /logs/verifier
cd /app
F=/tests/fixtures
pass=0
total=8

if [ -f /app/vm.js ]; then
  # 1. recursive-factorial sample trace
  if node /app/vm.js samples/fact6.elf --trace >/tmp/ag1 2>/dev/null && cmp -s /tmp/ag1 "$F/expected_fact6.trace"; then pass=$((pass+1)); fi
  # 2. sample snapshot
  if node /app/vm.js samples/fact6.elf --snapshot >/tmp/ag2 2>/dev/null && cmp -s /tmp/ag2 "$F/expected_fact6.snapshot.json"; then pass=$((pass+1)); fi
  # 3. trap handling: segv must be reported with status 139
  node /app/vm.js samples/segv.elf --trace >/tmp/ag3 2>/dev/null; rc3=$?
  if [ "$rc3" = "139" ] && cmp -s /tmp/ag3 "$F/expected_segv.trace"; then pass=$((pass+1)); fi
  # 4-8. hidden programs (assembled here, invisible to the agent)
  if python3 tools/asm.py "$F/hidden_fact.s" -o /tmp/hidden.elf >/dev/null 2>&1; then
    # input 6: trace + snapshot + plain
    if node /app/vm.js /tmp/hidden.elf --stdin "$F/in6.txt" --trace >/tmp/ag4 2>/dev/null && cmp -s /tmp/ag4 "$F/expected_hidden_fact6.trace"; then pass=$((pass+1)); fi
    if node /app/vm.js /tmp/hidden.elf --stdin "$F/in6.txt" --snapshot >/tmp/ag5 2>/dev/null && cmp -s /tmp/ag5 "$F/expected_hidden_fact6.snapshot.json"; then pass=$((pass+1)); fi
    node /app/vm.js /tmp/hidden.elf --stdin "$F/in6.txt" >/tmp/ag6 2>/dev/null; rc6=$?
    if [ "$rc6" = "0" ] && cmp -s /tmp/ag6 "$F/expected_hidden_fact6.out"; then pass=$((pass+1)); fi
    # input 9: plain + trace
    if node /app/vm.js /tmp/hidden.elf --stdin "$F/in9.txt" --trace >/tmp/ag7 2>/dev/null && cmp -s /tmp/ag7 "$F/expected_hidden_fact9.trace"; then pass=$((pass+1)); fi
    node /app/vm.js /tmp/hidden.elf --stdin "$F/in9.txt" >/tmp/ag8 2>/dev/null; rc8=$?
    if [ "$rc8" = "0" ] && cmp -s /tmp/ag8 "$F/expected_hidden_fact9.out"; then pass=$((pass+1)); fi
  fi
fi

reward=$(python3 -c "print('%.2f' % ($pass/$total))")
echo "$reward" > /logs/verifier/reward.txt