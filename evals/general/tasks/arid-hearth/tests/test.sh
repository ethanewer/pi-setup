#!/usr/bin/env bash
# arid-hearth verifier: runs the agent's automation on 4 hidden scenarios and
# checks deliverables, then writes a numeric reward.
set -uo pipefail

mkdir -p /logs/verifier

fail=0
total=0

base=/tests/hidden
for casedir in "$base"/*/; do
  [ -d "$casedir" ] || continue
  cp /app/list_ops.sh /app/list_ops.sh.bak 2>/dev/null || true
  python3 /app/list/store.py reset
  # run the independent scenario; only membership output should reach stdout
  out=$(bash "$casedir/scenario.sh" 2>/dev/null)
  exp=$(cat "$casedir/expected.txt")
  total=$((total + 1))
  if [ "$out" = "$exp" ]; then
    echo "case $(basename "$casedir"): PASS"
  else
    echo "case $(basename "$casedir"): FAIL"
    echo "  expected: [$exp]"; echo "  got:      [$out]"
    fail=$((fail + 1))
  fi
done

# Deliverable: policy must be open-but-confirm
pol=$(python3 /app/list/store.py policy 2>/dev/null)
[ "$pol" = "open-confirm" ] && polok=1 || polok=0

# Deliverable: list_ops.sh present + executable
[ -x /app/list_ops.sh ] && opsok=1 || opsok=0

# Deliverable: subscribe.log records a real pending + confirmed round-trip
oklog=0
if [ -f /app/subscribe.log ]; then
  grep -q 'status=pending' /app/subscribe.log && \
  grep -q 'status=confirmed' /app/subscribe.log && oklog=1
fi

echo "policy_ok=$polok ops_ok=$opsok log_ok=$oklog fail=$fail total=$total"

reward=0
if [ "$total" -gt 0 ] && [ "$fail" -eq 0 ] && [ "$polok" -eq 1 ] && [ "$opsok" -eq 1 ] && [ "$oklog" -eq 1 ]; then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0