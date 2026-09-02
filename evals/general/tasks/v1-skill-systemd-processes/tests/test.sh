#!/usr/bin/env bash
mkdir -p /logs/verifier
reward=0

if [ -f /app/watcher.service ]; then
  content=$(cat /app/watcher.service)
  has_unit=$([[ "$content" == *"[Unit]"* ]] && echo 1 || echo 0)
  has_service=$([[ "$content" == *"[Service]"* ]] && echo 1 || echo 0)
  has_install=$([[ "$content" == *"[Install]"* ]] && echo 1 || echo 0)
  has_exec=$([[ "$content" == *"/app/watcher.sh"* ]] && echo 1 || echo 0)
  no_stale=$([[ "$content" == *"/app/missing_watcher.sh"* ]] && echo 0 || echo 1)

  # ExecStart must specifically reference watcher.sh for the check to be meaningful.
  exec_ok=0
  if echo "$content" | grep -qE '[[:space:]]*ExecStart[[:space:]]*=[[:space:]]*/app/watcher\.sh'; then
    exec_ok=1
  fi

  if [ "$has_unit" = "1" ] && [ "$has_service" = "1" ] && [ "$has_install" = "1" ] && [ "$exec_ok" = "1" ] && [ "$no_stale" = "1" ]; then
    reward=1
  fi
fi

echo "$reward" > /logs/verifier/reward.txt