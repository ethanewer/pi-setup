#!/usr/bin/env bash
# Watcher service main process.
echo "watcher started pid=$PID"
while true; do
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) heartbeat" >> /app/watcher.log
  sleep 1
done