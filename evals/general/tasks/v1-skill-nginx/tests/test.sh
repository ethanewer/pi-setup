#!/bin/bash

# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0

if [ -f /app/nginx.conf ]; then
  # Stop any lingering nginx instances so restart/bind is deterministic.
  for p in $(ps -eo pid,args 2>/dev/null | grep -i 'nginx' | awk '{print $1}'); do
    kill "$p" 2>/dev/null || true
  done
  sleep 0.3

  if nginx -t -c /app/nginx.conf 2>/dev/null; then
    if nginx -c /app/nginx.conf 2>/dev/null; then
      sleep 0.5
      curl -s -m 5 -i http://127.0.0.1:8090/ > /tmp/curl_out 2>/dev/null
      if [ -s /tmp/curl_out ]; then
        txt=$(tr -d '\r' < /tmp/curl_out)
        if grep -qi 'X-Harbor-Task: nginx' <<<"$txt"; then
          if grep -q 'Harbor nginx probe index' <<<"$txt"; then
            reward=1
          fi
        fi
      fi
    fi
  fi
fi

echo "$reward" > /logs/verifier/reward.txt