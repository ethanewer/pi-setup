#!/bin/bash
# Container entrypoint for marble-shard.
# Starts the cache-shard keeper in the background, then runs the real command.
set -e
if [ -x /app/shardd.py ]; then
  nohup /usr/bin/env python3 /app/shardd.py >/tmp/shardd.log 2>&1 &
  sleep 1
fi
exec "$@"
