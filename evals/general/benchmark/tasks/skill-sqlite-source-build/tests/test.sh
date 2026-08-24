#!/bin/bash
mkdir -p /logs/verifier
reward=0

if [ -f /app/sqlite3 ] && [ $(wc -c < /app/sqlite3) -gt 500000 ]; then
  out=$(/app/sqlite3 /app/sales.db "SELECT item, SUM(qty) FROM sales GROUP BY item ORDER BY item;" 2>/dev/null)
  if [ -n "$out" ] && [ -f /app/result.txt ]; then
    norm() { tr -d '\r' | sed 's/[[:space:]]*$//' | grep -v '^[[:space:]]*$'; }
    expect=$(printf '%s' "$out" | norm)
    got=$(cat /app/result.txt | norm)
    lines=$(printf '%s\n' "$out" | norm)
    if [ "$expect" = "$got" ] && printf '%s\n' "$lines" | grep -q 'apple|9' && \
       printf '%s\n' "$lines" | grep -q 'banana|6' && \
       printf '%s\n' "$lines" | grep -q 'cherry|7'; then
      reward=1
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt