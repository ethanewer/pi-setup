#!/bin/bash
mkdir -p /logs/verifier
reward=0
stubs_ok=0
if [ -f /app/echo_pb2.py ] && [ -f /app/echo_pb2_grpc.py ]; then
  stubs_ok=1
fi
if [ "$stubs_ok" = "1" ] && [ -f /app/answer.txt ]; then
  got=$(cat /app/answer.txt | tr -d '\r\n')
  if [ "$got" = "HELLO, NEO" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt