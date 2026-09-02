#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/plan.txt ]; then
  content=$(cat /app/plan.txt 2>/dev/null)
  # The plan for an indexed lookup must say SEARCH ... USING INDEX idx_orders_customer.
  has_index=$(grep -c "idx_orders_customer" /app/plan.txt)
  has_search=$(grep -c "SEARCH" /app/plan.txt)
  has_scan=$(grep -c "SCAN" /app/plan.txt)
  if [ "$has_index" -ge 1 ] && [ "$has_search" -ge 1 ] && [ "$has_scan" -eq 0 ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt