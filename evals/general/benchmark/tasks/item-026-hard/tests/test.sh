#!/bin/bash
# Verifier for item-026-hard.
mkdir -p /logs/verifier
cd /app

SRC=/tests/test_regression.py
if [ ! -f "$SRC" ]; then SRC=/app/tests/test_regression.py; fi
cp "$SRC" /tmp/test_regression.py

python3 -m pytest /tmp/test_regression.py -q >/tmp/pt_out.txt 2>&1
PT=$?

st=$(git status --porcelain --untracked-files=no 2>/dev/null | wc -l)
commits=$(git rev-list --count HEAD 2>/dev/null | tr -d '\n')

reward=0
if [ "$PT" = "0" ] && [ "$st" = "0" ] && [ -n "$commits" ] && [ "$commits" -ge "2" ]; then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt