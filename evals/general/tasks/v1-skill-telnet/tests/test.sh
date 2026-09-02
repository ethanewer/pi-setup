#!/usr/bin/env bash
mkdir -p /logs/verifier
reward=0

secret_ok=$( [ -f /app/secret.txt ] && [ "$(cat /app/secret.txt | tr -d '\r\n')" = "open-sesame-42" ] && echo 1 || echo 0 )

log_ok=0
if [ -f /app/server.log ]; then
  if grep -q '^GIVE-KEY$' /app/server.log; then
    log_ok=1
  fi
fi

if [ "$secret_ok" = "1" ] && [ "$log_ok" = "1" ]; then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt