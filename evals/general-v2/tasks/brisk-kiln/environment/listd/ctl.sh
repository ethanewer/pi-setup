#!/usr/bin/env bash
#
# ctl.sh -- Grebe Lake listd service control (image infrastructure).
#
#   start | stop | restart | status
#
# The daemon reads its configuration ONLY from the canonical path
# /etc/listd/lists.conf. If that file is missing or invalid, start/restart
# fail (the daemon exits 2) and this script reports failure.
set -u

PIDF=/var/run/listd.pid
LOG=/var/log/listd.log
DAEMON=/opt/listd/listd.py

port_of() {
  python3 - <<'PY' 2>/dev/null
import configparser
cp = configparser.ConfigParser()
cp.read("/etc/listd/lists.conf")
print(int(cp.get("global", "port", fallback="8418")))
PY
}

PORT="$(port_of)"
HEALTH_URL="http://127.0.0.1:${PORT}/health"
}

health_ok() {
  python3 - "$PORT" <<'PY'
import sys, urllib.request
port = sys.argv[1]
try:
    with urllib.request.urlopen("http://127.0.0.1:%s/health" % port, timeout=2) as r:
        return 0 if r.status == 200 else 1
except Exception:
    return 1
PY
}

start() {
  if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then
    echo "listd: already running (pid $(cat "$PIDF"))" >&2
    return 0
  fi
  # Clean up any stray daemon not tracked by the pidfile.
  pkill -f "$DAEMON" 2>/dev/null || true
  sleep 0.3
  nohup python3 "$DAEMON" >>"$LOG" 2>&1 &
  echo $! > "$PIDF"
  for _ in $(seq 1 50); do
    if health_ok; then
      return 0
    fi
    sleep 0.2
  done
  echo "listd: did not become healthy on port $PORT" >&2
  tail -5 "$LOG" >&2 2>/dev/null || true
  return 1
}

stop_daemon() {
  if [ -f "$PIDF" ]; then
    pid="$(cat "$PIDF" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      for _ in $(seq 1 50); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2
      done
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$PIDF"
  fi
  pkill -f "$DAEMON" 2>/dev/null || true
  return 0
}

case "${1:-}" in
  start)   start ;;
  stop)    stop_daemon ;;
  restart) stop_daemon; sleep 0.3; start ;;
  status)  if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null && health_ok; then
             echo "listd: running (pid $(cat "$PIDF"))"; exit 0
           else
             echo "listd: not running" >&2; exit 1
           fi ;;
  *) echo "usage: ctl.sh start|stop|restart|status" >&2; exit 2 ;;
esac
