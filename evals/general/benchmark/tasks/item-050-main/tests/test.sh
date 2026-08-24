#!/bin/bash
mkdir -p /logs/verifier
reward=0

# 1) config must be syntactically valid
if ! nginx -t >/tmp/nginx_t.log 2>&1; then
  echo "$reward" > /logs/verifier/reward.txt
  exit 0
fi

# 2) bring the server up from a clean rate-limit state. A full restart
#    (stop+start) re-allocates the shared `limit_req` zone, resetting the
#    token bucket so the agent's own burst testing cannot skew these checks.
nginx -s stop 2>/dev/null
sleep 0.3
nginx 2>/dev/null

# wait until it answers
up=0
for i in $(seq 1 30); do
  if curl -s -o /dev/null "http://127.0.0.1:8000/status" 2>/dev/null; then
    up=1; break
  fi
  sleep 0.2
done
if [ "$up" != "1" ]; then
  echo "$reward" > /logs/verifier/reward.txt
  exit 0
fi

ok=1

# 3) normal request -> 200
code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/status)
if [ "$code" != "200" ]; then ok=0; fi

# 4) rapid burst -> at least 3 x 429 and some 200
n429=0; n200=0
for i in $(seq 1 16); do
  c=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/status)
  if [ "$c" = "429" ]; then n429=$((n429 + 1)); elif [ "$c" = "200" ]; then n200=$((n200 + 1)); fi
done
if [ "$n429" -lt 3 ]; then ok=0; fi
if [ "$n200" -lt 1 ]; then ok=0; fi

# 5) spaced request -> 200
sleep 1.6
code2=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/status)
if [ "$code2" != "200" ]; then ok=0; fi

# 6) access log exists, contains 200 and 429 status lines
LOG=/var/log/nginx/api_access.log
if [ ! -f "$LOG" ] || [ ! -s "$LOG" ]; then
  ok=0
else
  # Parse trailing HTTP status codes from the custom api_log format.
  # Status is the last token of each line; tolerate a trailing CR (CRLF).
  log_ok=$(python3 - <<'PYLOG'
import re
codes = set()
for line in open('/var/log/nginx/api_access.log', errors='replace'):
    m = re.search(r'\"\s+(\d{3})\s*$', line)
    if m:
        codes.add(int(m.group(1)))
print(1 if {200, 429} <= codes else 0)
PYLOG
)
  if [ "$log_ok" != "1" ]; then ok=0; fi
fi

echo "n429=$n429 n200=$n200" > /tmp/nginx_stats.txt
echo "$ok" > /logs/verifier/reward.txt