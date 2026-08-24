#!/bin/bash
set -euo pipefail

strace -e trace=read,write -o /app/trace.txt /app/prog > /dev/null 2>&1

reads=$(grep -c '^read(' /app/trace.txt || true)
writes=$(grep -c '^write(' /app/trace.txt || true)
printf 'reads=%s\nwrites=%s\n' "$reads" "$writes" > /app/syscalls.txt