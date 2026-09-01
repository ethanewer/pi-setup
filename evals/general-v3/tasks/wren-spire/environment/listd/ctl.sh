#!/usr/bin/env bash
#
# ctl.sh -- control script for the Hollowpine listd daemon (image infra).
#
# Subcommands: start | stop | restart | status | dump
set -u

PIDFILE=/var/run/listd.pid
LOG=/var/log/listd.log
DAEMON=/opt/listd/listd.py
STATE=/var/lib/listd/loaded.json

is_running() {
  [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

start() {
  if is_running; then
    return 0
  fi
  rm -f "$PIDFILE"
  rm -f "$STATE" "$STATE.tmp"
  nohup python3 "$DAEMON" >>"$LOG" 2>&1 &
  echo $! > "$PIDFILE"
  # wait until the daemon has republished its loaded state (fresh, not stale)
  for _ in $(seq 1 40); do
    [ -f "$STATE" ] && return 0
    sleep 0.5
  done
  echo "ctl: listd did not publish state" >&2
  return 1
}

stop() {
  if is_running; then
    pid="$(cat "$PIDFILE")"
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 40); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.25
    done
  fi
  rm -f "$PIDFILE"
}

dump() {
  [ -f "$STATE" ] || { echo "ctl: no loaded state (daemon not running?)" >&2; exit 1; }
  cat "$STATE"
}

cmd="${1:-status}"
case "$cmd" in
  start)   start ;;
  stop)    stop ;;
  restart) stop; start ;;
  status)  if is_running; then echo "running (pid $(cat "$PIDFILE"))"; else echo "stopped"; exit 1; fi ;;
  dump)    dump ;;
  *)       echo "unknown ctl subcommand: $cmd" >&2; exit 2 ;;
esac
exit 0
