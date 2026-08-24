#!/bin/bash

reward=0
if [ -f /app/websockify_answer.txt ]; then
  txt=$(tr '[:upper:]' '[:lower:]' < /app/websockify_answer.txt)
  has_wb=$(grep -c 'websocket' <<<"$txt")
  has_tcp=$(grep -c 'tcp' <<<"$txt")
  has_novnc=$(grep -c 'novnc' <<<"$txt")
  has_fw=$(grep -cE 'browser|bridge' <<<"$txt")
  if [ "$has_wb" -gt 0 ] && [ "$has_tcp" -gt 0 ] && [ "$has_novnc" -gt 0 ] && [ "$has_fw" -gt 0 ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt