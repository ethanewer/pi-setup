#!/bin/bash
# Verifier for scupper-sail (executes-deliverable).
#
# Executes the two deliverable artifacts with the cascade resolver at
# /tests/resolver.py: it parses /app/styles.css with tinycss2, resolves
# declarations against the hidden viewport fixtures under /tests/hidden
# (media layers, container layers, specificity, custom-property inheritance
# and var() substitution), checks /app/dashboard.html against the markup
# contract, and asserts the media/container structure and the named custom
# properties. Writes reward 1 only if every structural and behavioural
# assertion passes; anything else writes 0. The resolver prints a readable
# failure list to stdout, which lands in verifier/test-stdout.txt.
#
# Reward is written on every exit path. The trap below guarantees a 0 if this
# shell is interrupted before the reward file exists; the branch below writes
# exactly one of 0 or 1 and exits immediately afterwards, so no later line can
# overwrite a failure reward with a success one.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

if python3 /tests/resolver.py /app/styles.css /app/dashboard.html /tests/hidden; then
  echo "reward: 1"
  echo 1 > /logs/verifier/reward.txt
  exit 0
fi
echo "reward: 0"
echo 0 > /logs/verifier/reward.txt
exit 0