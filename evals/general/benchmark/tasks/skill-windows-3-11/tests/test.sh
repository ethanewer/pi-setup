#!/bin/bash

reward=0
if [ -f /app/windows_answer.txt ]; then
  txt=$(tr '[:upper:]' '[:lower:]' < /app/windows_answer.txt)
  has_wg=$(grep -c 'workgroups' <<<"$txt")
  has_dos=$(grep -c 'dos' <<<"$txt")
  has_pm=$(grep -c 'program manager' <<<"$txt")
  has_gui=$(grep -cE 'gui|shell' <<<"$txt")
  if [ "$has_wg" -gt 0 ] && [ "$has_dos" -gt 0 ] && [ "$has_pm" -gt 0 ] && [ "$has_gui" -gt 0 ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt