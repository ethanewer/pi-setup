#!/usr/bin/env bash
#
# keelson-buoy verifier. The heavy assertions live in /tests/verify.py
# (referenced by an absolute path so the suite lint can follow them into the
# deliverable-execution and answer-leak checks). This script owns the reward:
# it runs the verifier body, prints its readable failure list, and writes a
# strictly binary reward on every exit path. An untouched container has no
# /app/repair.py and an unrepaired column, so it scores 0; a correct repair
# satisfies every pristine-state assertion and scores 1.
set -u

# Standard reward guard: converts "no verdict" into a loud 0.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier

TMP=$(mktemp -d)
TIMEOUT_CMD=$(command -v timeout || true)
[ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""

# Run the assertions. rc is the only signal we take from the helper; the
# reward below is written from literal 0/1 values, never from $?.
$TIMEOUT_CMD 520 python3 /tests/verify.py > "$TMP/verify.out" 2>&1
rc=$?

# The readable failure list lands in verifier/test-stdout.txt and is the
# primary diagnostic for any 0.
cat "$TMP/verify.out"

if [ "$rc" -eq 0 ]; then
  printf 1 > /logs/verifier/reward.txt
else
  printf 0 > /logs/verifier/reward.txt
fi

rm -rf "$TMP"
exit 0