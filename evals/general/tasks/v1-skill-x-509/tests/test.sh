#!/bin/bash

# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

reward=0
if [ -f /app/cert.pem ]; then
  subj=$(openssl x509 -in /app/cert.pem -noout -subject 2>/tmp/x509.log)
  if [ -n "$subj" ] && echo "$subj" | grep -q "example.com"; then
    if openssl x509 -in /app/cert.pem -noout -checkend 0 >/dev/null 2>&1; then
      reward=1
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt