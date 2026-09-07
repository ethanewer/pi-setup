#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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