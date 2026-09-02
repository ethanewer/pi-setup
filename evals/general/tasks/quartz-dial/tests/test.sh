#!/bin/bash
# Verifier driver for tasks/quartz-dial (executes-deliverable).
#
# Runs the independent Python verifier at /tests/helper/verify.py, which
# re-runs every /app deliverable (filter_locale.py, tokenize.py, bpe.py,
# detect_lang.py, fetch_leaderboard.py), checks the offline model/tokenizer
# load, validates the harness task config against hidden query/title data, and
# parses the leaderboard mirror directly.  The numeric reward is persisted to
# /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

# Keep the stdlib `tokenize` importable even though /app holds tokenize.py.
export PYTHONSAFEPATH=1

out=$(python3 /tests/helper/verify.py 2>/tmp/verify_stderr.log || true)
echo "$out"

case "$out" in
  *REWARD=1*) reward=1 ;;
  *)          reward=0 ;;
esac

if [ "$out" = "REWARD=1" ]; then
  echo "REWARD=$reward"
fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
