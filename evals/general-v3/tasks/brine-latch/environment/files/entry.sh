#!/bin/bash
# Container entrypoint for brine-latch: starts the ColdBrine relay daemon
# (which rotates = unlinks its snapshot while holding the fd open), then runs
# the real command.
set -e
if [ -x /app/keeper.py ]; then
  nohup /usr/bin/env python3 /app/keeper.py >/tmp/brine-vault/relay.log 2>&1 &
  sleep 1
fi
exec "$@"
