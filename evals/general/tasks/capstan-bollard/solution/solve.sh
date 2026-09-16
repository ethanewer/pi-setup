#!/bin/bash
# Oracle for capstan-bollard: repair the real scipy tree at /app/src so that
# computing the repr of an optimizer result with an empty-dict field no longer
# raises ValueError, then prove it with the shipped reproducer.
set -u

test -d /app/src || { echo "oracle: /app/src tree missing" >&2; exit 1; }

python3 /solution/apply_fix.py || { echo "oracle: fix application failed" >&2; exit 1; }

python3 /app/reproduce.py || { echo "oracle: reproduce.py still crashes after fix" >&2; exit 1; }

echo "oracle: tree repaired, /app/reproduce.py exits 0"