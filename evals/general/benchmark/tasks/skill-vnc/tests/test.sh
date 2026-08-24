#!/bin/bash

reward=0
if [ -f /app/vnc_answer.txt ]; then
  txt=$(tr '[:upper:]' '[:lower:]' < /app/vnc_answer.txt)
  has_rfb=$(echo "$txt" | grep -c 'rfb')
  has_port=$(echo "$txt" | grep -c '5900')
  has_desktop=$(echo "$txt" | grep -c 'desktop')
  has_framebuffer=$(echo "$txt" | grep -c 'framebuffer')
  if [ "$has_rfb" -gt 0 ] && [ "$has_port" -gt 0 ] && ( [ "$has_desktop" -gt 0 ] || [ "$has_framebuffer" -gt 0 ] ); then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt