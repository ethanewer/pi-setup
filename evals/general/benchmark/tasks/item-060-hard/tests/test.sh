#!/bin/bash
# Verifier for item-060-hard.
mkdir -p /logs/verifier

DIR="$(cd "$(dirname "$0")" && pwd)"
reward=$(python3 "$DIR/checker.py" 2>/dev/null)

case "$reward" in
  1|0.5|0) ;;
  *) reward=0 ;;
esac

echo "$reward" > /logs/verifier/reward.txt
exit 0