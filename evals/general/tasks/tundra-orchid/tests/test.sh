#!/usr/bin/env bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
cd "$(dirname "$0")"
mkdir -p /logs/verifier
res=$(python3 /tests/run_verify.py 2>/dev/null | tr -d '[:space:]')
case "${res:-}" in
  1) echo 1 > /logs/verifier/reward.txt ;;
  *) echo 0 > /logs/verifier/reward.txt ;;
esac
exit 0