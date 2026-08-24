#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0

pkill -f 'python3 -m http.server 8792' 2>/dev/null
sleep 0.4

# listener_pids: space-separated PIDs of processes currently LISTENING on :8792
listener_pids() {
  local out=""
  if command -v lsof >/dev/null 2>&1; then
    out=$(lsof -iTCP:8792 -sTCP:LISTEN -t 2>/dev/null)
  fi
  if [ -z "$out" ] && command -v ss >/dev/null 2>&1; then
    out=$(ss -ltnp 2>/dev/null | grep -E ':8792 ' | grep -oE 'pid=[0-9]+' | sed 's/pid=//')
  fi
  echo "$out"
}

run_bounded() {
  local script="$1" port="$2"
  if command -v timeout >/dev/null 2>&1; then
    timeout 10 bash "$script" "$port" 2>/dev/null
  else
    bash "$script" "$port" 2>/dev/null
  fi
}

if [ -f "$APP/findport.sh" ] && [ -f "$APP/killport.sh" ]; then
  ( cd /tmp && python3 -m http.server 8792 --bind 127.0.0.1 >/dev/null 2>&1 ) &
  sleep 1.0

  if listener_pids | grep -q '[0-9]'; then
    fp=$(run_bounded "$APP/findport.sh" 8792)
    found=$(echo "$fp" | grep -oE '[0-9]+' | head -1)
    # the PID reported by findport.sh must actually be one of the live listeners
    if [ -n "$found" ] && echo "$(listener_pids)" | grep -qw "$found"; then
      run_bounded "$APP/killport.sh" 8792
      sleep 1.0
      if [ -z "$(listener_pids)" ]; then
        reward=1
      fi
    fi
  fi
  pkill -f 'python3 -m http.server 8792' 2>/dev/null
fi
printf '%s' "$reward" > /logs/verifier/reward.txt