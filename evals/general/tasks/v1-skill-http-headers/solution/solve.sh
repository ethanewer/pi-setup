#!/bin/bash
set -euo pipefail
python3 /app/server.py &
sleep 1
curl -s -D /app/hdrs.txt -o /dev/null -H "X-Token: secret42" http://127.0.0.1:8080/
# Extract value after 'X-Recv-Token:' (case-insensitive) from the header dump.
val=""
while read -r line; do
  if echo "$line" | grep -qi "^X-Recv-Token:"; then
    val=$(echo "$line" | sed -E 's/^[^:]+:[[:space:]]*//' | tr -d '\r')
  fi
done < /app/hdrs.txt
printf '%s' "$val" > /app/header.txt
kill %1 2>/dev/null || true