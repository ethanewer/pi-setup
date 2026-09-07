#!/usr/bin/env bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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