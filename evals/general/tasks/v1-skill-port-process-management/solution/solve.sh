#!/bin/bash
set -euo pipefail

cat > /app/findport.sh <<'P'
#!/bin/bash
PORT="$1"
if command -v lsof >/dev/null 2>&1; then
  pids=$(lsof -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null)
elif command -v ss >/dev/null 2>&1; then
  pids=$(ss -ltnp 2>/dev/null | grep -E ":$PORT " | grep -oE 'pid=[0-9]+' | sed 's/pid=//' | uniq)
else
  pids=$(fuser "$PORT" 2>/dev/null)
fi
pids=$(echo "$pids" | grep -E '^[0-9]+$')
if [ -z "$pids" ]; then
  exit 1
fi
echo "$pids"
exit 0
P

cat > /app/killport.sh <<'P'
#!/bin/bash
PORT="$1"
if command -v lsof >/dev/null 2>&1; then
  pids=$(lsof -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null)
else
  pids=$(ss -ltnp 2>/dev/null | grep -E ":$PORT " | grep -oE 'pid=[0-9]+' | sed 's/pid=//' | uniq)
fi
for p in $pids; do
  if [ -n "$p" ]; then
    kill "$p" 2>/dev/null
  fi
done
sleep 0.4
if command -v lsof >/dev/null 2>&1; then
  left=$(lsof -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null)
else
  left=$(ss -ltn 2>/dev/null | grep -E ":$PORT ")
fi
if [ -n "$left" ]; then
  exit 1
fi
exit 0
P

chmod +x /app/findport.sh /app/killport.sh