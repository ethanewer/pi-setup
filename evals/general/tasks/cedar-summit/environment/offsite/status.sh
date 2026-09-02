#!/bin/bash
# Health snapshot of the offsite microservices.
set -u
declare -A PORTS=( [coordinator]=8701 [mara]=8702 [jonas]=8703 [priya]=8704 )
for svc in coordinator mara jonas priya; do
  port=${PORTS[$svc]}
  if curl -s -m 2 "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
    echo "status.sh: ${svc} up on :${port}"
  else
    echo "status.sh: ${svc} DOWN on :${port}"
  fi
done
