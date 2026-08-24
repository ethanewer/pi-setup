#!/bin/bash
reward=0
mkdir -p /logs/verifier
tmp=/tmp/arena_ref; rm -rf "$tmp"; mkdir -p "$tmp"
cp /tests/main.c /app/project/arena.c /app/project/arena.h "$tmp"/
if ( cd "$tmp" && gcc -std=c11 -Wall -Wextra arena.c main.c -o arena_test 2>/dev/null && ./arena_test 2>/dev/null > out.txt ); then
  line=$(tr -d '\r\n' < "$tmp/out.txt" 2>/dev/null)
  if [ "$line" = "ALLOC_OK" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt