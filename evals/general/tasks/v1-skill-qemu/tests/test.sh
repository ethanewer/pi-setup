#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/qemu_cmd.txt ]; then
  line=$(cat /app/qemu_cmd.txt | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//')
  if [[ $line == qemu-system-x86_64* ]] \
     && ( grep -q '\-m 8192' <<< "$line" ) \
     && ( grep -q '\-smp 4' <<< "$line" ) \
     && ( grep -q '\-drive file=/app/guest.img,format=raw' <<< "$line" ) \
     && ( grep -q '\-display none' <<< "$line" ); then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt
