#!/bin/bash
reward=0
mkdir -p /logs/verifier
if [ -f /app/fetched.json ]; then
  # Verify by reading the expected raw body from a fresh local server.
  tmp=/tmp/curl_ref
  rm -rf "$tmp"; mkdir -p /app/probe_root 2>/dev/null
  src=/app/webroot/public/sample.json
  if [ -f "$src" ]; then
    expected=$(cat "$src")
    got=$(cat /app/fetched.json)
    if [ -n "$got" ] && [ "$got" = "$expected" ]; then
      reward=1
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt