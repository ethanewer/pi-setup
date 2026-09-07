#!/usr/bin/env bash
# Verifier for flint-fathom (executes-deliverable).
# Delegates all checking to /tests/check.py (a helper under tests/), which
# re-executes /app/detect_frames.py on the clip and on hidden jump clips and
# /app/extract_commands.py on the fixture and a hidden transcript, re-downloads
# with /app/fetch_media.sh, and validates every deliverable. Reward = 1 iff all
# checks pass.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

python3 /tests/check.py
rc=$?

if [ "$rc" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0