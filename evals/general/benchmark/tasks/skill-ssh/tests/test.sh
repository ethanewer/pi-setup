#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/ssh.txt ]; then
  content=$(cat /app/ssh.txt | tr -d '\r')
  if [ "$content" = "ssh-secret-hello-world" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt