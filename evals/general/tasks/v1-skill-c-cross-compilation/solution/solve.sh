#!/usr/bin/env bash
set -euo pipefail

aarch64-linux-gnu-gcc -static -O2 -o /app/cross/hello_arm /app/cross/hello.c
printf 'aarch64\n' > /app/cross/target.txt

file /app/cross/hello_arm
test "$(cat /app/cross/target.txt)" = "aarch64"