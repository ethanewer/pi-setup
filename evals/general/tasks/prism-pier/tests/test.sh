#!/bin/bash
# Verifier for prism-pier. Runs each deliverable against hidden inputs using
# tests/ref.py as the reference oracle, then checks /app/map.txt.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

reward=1

run() {
    desc="$1"; shift
    if ! python3 /tests/ref.py "$@"; then
        echo "FAIL: $desc"
        reward=0
    else
        echo "ok: $desc"
    fi
}

mkdir -p /logs/verifier

HIDDEN=/tests/hidden
if [ -d "$HIDDEN" ]; then
    for t in "$HIDDEN"/tile_*.json; do
        [ -e "$t" ] && run "expand $(basename "$t")" expand "$t"
    done
    for a in "$HIDDEN"/arc_*.json; do
        [ -e "$a" ] && run "arc $(basename "$a")" arc "$a"
    done
    for s in "$HIDDEN"/sq_*.json; do
        [ -e "$s" ] && run "squares $(basename "$s")" sq "$s"
    done
else
    echo "no hidden dir"
    reward=0
fi

run "final map" mapfile

echo "reward=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0