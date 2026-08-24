#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/pkg/config.mk ] && [ -f /app/pkg/built/output.txt ]; then
  # recompute expected from config.mk
  version=$(grep '^VERSION' /app/pkg/config.mk | tr -d '\r\n' | sed 's/^VERSION[[:space:]]*=[[:space:]]*//')
  expected="APP_VERSION=$version"
  content=$(tr -d '\r\n' < /app/pkg/built/output.txt)
  if [ "$content" = "$expected" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt