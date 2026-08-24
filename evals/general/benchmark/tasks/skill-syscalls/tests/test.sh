#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/syscalls.txt ]; then
  strace -e trace=read,write -o /tmp/verifier_trace.txt /app/prog > /dev/null 2>&1
  exp_reads=$(grep -c '^read(' /tmp/verifier_trace.txt || true)
  exp_writes=$(grep -c '^write(' /tmp/verifier_trace.txt || true)

  got_reads=$(grep -o '^reads=[0-9]*' /app/syscalls.txt | head -1 | cut -d= -f2)
  got_writes=$(grep -o '^writes=[0-9]*' /app/syscalls.txt | head -1 | cut -d= -f2)

  if [ -n "$got_reads" ] && [ -n "$got_writes" ]; then
    if [ "$got_reads" = "$exp_reads" ] && [ "$got_writes" = "$exp_writes" ]; then
      reward=1
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt