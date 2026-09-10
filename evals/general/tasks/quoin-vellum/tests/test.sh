#!/usr/bin/env bash
# Verifier for tasks/quoin-vellum (executes-deliverable).
#
# Executes the agent's deliverable /app/train_topics.py on every hidden corpus,
# reloads each produced model through gensim's own loader and scores c_v
# coherence and topic-word purity (see /tests/check.py for the thresholds and
# the readable per-corpus verdicts, which land in verifier/test-stdout.txt).
#
# Guarantee a reward on every exit path. Without this a verifier that raises
# while inspecting the agent's deliverable writes nothing at all, which yields
# a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

if python3 /tests/check.py /app/train_topics.py /tests/hidden; then
    reward=1
else
    reward=0
fi

echo "$reward" > /logs/verifier/reward.txt
echo "reward=${reward}"
exit 0
