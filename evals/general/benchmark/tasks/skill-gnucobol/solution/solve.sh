#!/bin/bash
set -euo pipefail
cobc -x -o /tmp/sumprobe /app/program.cob
/tmp/sumprobe > /tmp/sumprobe.out 2>/dev/null
# numeric display may be zero-padded; extract integer and write it
raw=$(grep -oE '[0-9]+' /tmp/sumprobe.out | head -1)
n=$(echo "$raw" | sed 's/^0*//')
if [ "$n" = "" ]; then n="0"; fi
printf '%s' "$n" > /app/answer.txt