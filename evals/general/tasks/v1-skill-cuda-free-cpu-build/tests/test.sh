#!/bin/bash
reward=0
mkdir -p /logs/verifier
if [ -f /app/project/run ]; then
  # Rebuild pristine CPU-mode sources in a scratch dir and capture expected output.
  tmp=/tmp/cuda_ref
  rm -rf "$tmp"; mkdir -p "$tmp"
  cp /tests/reference/main.cpp /tests/reference/build_config.h /tests/reference/Makefile "$tmp"/
  ( cd "$tmp" && make run >/dev/null 2>&1 && ./run > expected.txt )
  if [ -f "$tmp/expected.txt" ] && grep -q '^BUILD_TARGET=cpu$' "$tmp/expected.txt" \
     && grep -q '^BUILD_TARGET=cpu$' /app/run.txt 2>/dev/null; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt