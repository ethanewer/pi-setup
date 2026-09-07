#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -d /app/pulled/.git ]; then
  content=$(cat /app/pulled/README.txt 2>/dev/null | tr -d '\r\n')
  url=$(git -C /app/pulled remote get-url origin 2>/dev/null)
  if [ "$content" = "ssh-hello" ]; then
    # origin must be an SSH transport URL (ssh:// or user@host:path)
    if echo "$url" | grep -qE "ssh://|@127\.0\.0\.1|sshgit@"; then
      reward=1
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt