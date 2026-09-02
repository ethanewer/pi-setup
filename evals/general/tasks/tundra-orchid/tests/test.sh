#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"
mkdir -p /logs/verifier
res=$(python3 /tests/run_verify.py 2>/dev/null | tr -d '[:space:]')
case "${res:-}" in
  1) echo 1 > /logs/verifier/reward.txt ;;
  *) echo 0 > /logs/verifier/reward.txt ;;
esac
exit 0