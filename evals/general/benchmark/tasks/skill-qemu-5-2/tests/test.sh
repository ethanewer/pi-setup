#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/qemu_boot.txt ]; then
  line=$(cat /app/qemu_boot.txt | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//')
  check1=$(grep -q '^qemu-system-x86_64' <<< "$line")
  check2=$(grep -q '\-m 2048' <<< "$line")
  check3=$(grep -q '\-smp 2' <<< "$line")
  check4=$(grep -q 'file=/app/guest.iso' <<< "$line")
  check5=$(grep -q 'media=cdrom' <<< "$line")
  check6=$(grep -q '\-boot' <<< "$line")
  if $check1 $check2 $check3 $check4 $check5 $check6; then reward=1; fi
fi
echo "$reward" > /logs/verifier/reward.txt
