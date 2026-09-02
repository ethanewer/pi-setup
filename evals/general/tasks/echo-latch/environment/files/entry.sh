#!/bin/bash
# Container entrypoint for echo-latch.
# Starts the descriptor keeper in the background, then runs the real command.
set -e
if [ -x /app/latch_keeper.py ]; then
  nohup /usr/bin/env python3 /app/latch_keeper.py >/tmp/latch-keeper.log 2>&1 &
  sleep 1
fi
exec "$@"
