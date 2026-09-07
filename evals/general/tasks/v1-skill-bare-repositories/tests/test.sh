#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -d /app/harbor.git ]; then
  rm -rf /tmp/verify_clone
  if git clone /app/harbor.git /tmp/verify_clone >/dev/null 2>&1; then
    content=$(cat /tmp/verify_clone/README.md 2>/dev/null)
    if [ "$content" == "harbor-bare-repository" ]; then
      reward=1
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt
