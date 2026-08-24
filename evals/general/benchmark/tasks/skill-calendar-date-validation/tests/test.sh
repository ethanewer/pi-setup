#!/usr/bin/env bash
mkdir -p /logs/verifier

reward=0
if [ -f /app/dates_verified.txt ]; then
  if python3 - <<'PY_END'
import sys

def is_leap(y):
    return y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)

def is_valid(y, m, d):
    if not (1 <= y <= 9999 and 1 <= m <= 12 and 1 <= d <= 31):
        return False
    dim = [31, 29 if is_leap(y) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    return d <= dim[m - 1]

rows = []
for line in open("/app/dates.tsv"):
    line = line.strip()
    if not line:
        continue
    y, m, d = (int(x) for x in line.split("-"))
    rows.append("VALID" if is_valid(y, m, d) else "INVALID")

got = open("/app/dates_verified.txt").read().splitlines()
got = [g.rstrip("\r") for g in got]
sys.exit(0 if got == rows else 1)
PY_END
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt