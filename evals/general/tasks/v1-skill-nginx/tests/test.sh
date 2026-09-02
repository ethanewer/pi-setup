#!/bin/bash

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