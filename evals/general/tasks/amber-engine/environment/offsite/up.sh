#!/bin/bash
# Bring up the four offsite microservices (idempotent).
set -u
SVC_DIR=/opt/offsite/services
LOG_DIR=/var/log/offsite
mkdir -p "$LOG_DIR"

declare -A PORTS=( [coordinator]=8701 [mara]=8702 [jonas]=8703 [priya]=8704 )

for svc in coordinator mara jonas priya; do
  port=${PORTS[$svc]}
  if curl -s -m 2 "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
    echo "up.sh: ${svc} already up on :${port}"
    continue
  fi
  nohup python3 "${SVC_DIR}/${svc}.py" >>"${LOG_DIR}/${svc}.log" 2>&1 &
  echo $! >"${LOG_DIR}/${svc}.pid"
done

rc=0
for svc in coordinator mara jonas priya; do
  port=${PORTS[$svc]}
  ok=""
  for _ in $(seq 1 50); do
    if curl -s -m 2 "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
      ok=1; break
    fi
    sleep 0.2
  done
  if [ -n "$ok" ]; then
    echo "up.sh: ${svc} healthy on :${port}"
  else
    echo "up.sh: ${svc} FAILED to come up (see ${LOG_DIR}/${svc}.log)"
    rc=1
  fi
done
exit $rc
