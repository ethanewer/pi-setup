#!/bin/bash
# Stop the offsite microservices.
set -u
LOG_DIR=/var/log/offsite
for svc in coordinator mara jonas priya; do
  pidfile="${LOG_DIR}/${svc}.pid"
  if [ -f "$pidfile" ]; then
    pid=$(cat "$pidfile" 2>/dev/null || true)
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      echo "down.sh: stopped ${svc} (pid ${pid})"
    fi
    rm -f "$pidfile"
  fi
done
