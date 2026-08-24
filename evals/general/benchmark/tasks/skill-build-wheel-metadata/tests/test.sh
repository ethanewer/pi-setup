#!/usr/bin/env bash
mkdir -p /logs/verifier

p1=0   # wheel built, METADATA correct, importable
p2=0   # meta_report.txt correct

WHL=$(ls /app/dist/*.whl 2>/dev/null | head -1)
if [ -n "$WHL" ] && unzip -t "$WHL" >/dev/null 2>&1; then
  meta_ok=0
  META=$(unzip -p "$WHL" '*/METADATA' 2>/dev/null)
  if echo "$META" | grep -q '^Name: melonpkg' && \
     echo "$META" | grep -q '^Version: 1.4.0' && \
     echo "$META" | grep -q '^Requires-Python: >=3.8'; then
    meta_ok=1
  fi
  WDIR=/tmp/wheelcheck
  rm -rf "$WDIR" && mkdir -p "$WDIR"
  if [ "$meta_ok" = 1 ] && (cd "$WDIR" && unzip -q "$WHL" && \
     python3 -c "import sys; sys.path.insert(0, '.'); from pkg.core import add; assert add(2,3) == 5"); then
    p1=1
  fi
fi

if [ -f /app/meta_report.txt ]; then
  if grep -q '^Name: melonpkg' /app/meta_report.txt && grep -q '^Version: 1.4.0' /app/meta_report.txt; then
    p2=1
  fi
fi

reward=0
if [ "$p1" = 1 ] && [ "$p2" = 1 ]; then
  reward=1
elif [ "$p1" = 1 ] || [ "$p2" = 1 ]; then
  reward=0.5
fi
echo "$reward" > /logs/verifier/reward.txt