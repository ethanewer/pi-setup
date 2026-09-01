#!/bin/bash
# Verifier for kiln-vane: EXECUTES the deliverable module (/app/loom.py) — both
# its CLI form and its imported weave() function — against the visible fixture
# and every hidden case in /tests/hidden, and checks /app/swatch.json. Writes
# REWARD (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=1

# --- no-modify check on the supplied /app/tile.json -------------------------
if [ ! -f /app/tile.json ]; then
    echo "no-modify: /app/tile.json missing" >&2
    reward=0
else
    expected_sha="$(cat /tests/tile.sha256)"
    actual_sha="$(sha256sum /app/tile.json | awk '{print $1}')"
    if [ "$actual_sha" != "$expected_sha" ]; then
        echo "no-modify: /app/tile.json was modified" >&2
        reward=0
    fi
fi

# --- hidden cases: execute /app/loom.py via the reference oracle ------------
HIDDEN=/tests/hidden
if [ -d "$HIDDEN" ]; then
    cases="$(find "$HIDDEN" -mindepth 1 -maxdepth 1 -type d | sort)"
    if [ -z "$cases" ]; then
        echo "no hidden cases present"
        reward=0
    fi
    for c in $cases; do
        if ! python3 /tests/ref.py swatch "$c/tile.json" "$c/expected.json"; then
            echo "FAIL: hidden weave $(basename "$c")"
            reward=0
        else
            echo "ok: hidden weave $(basename "$c")"
        fi
    done
else
    echo "no hidden dir"
    reward=0
fi

# --- deliverable 1: /app/loom.py must exist and be importable ----------------
if [ ! -f /app/loom.py ]; then
    echo "FAIL: missing /app/loom.py"
    reward=0
else
    if ! python3 /app/loom.py /tests/visible_tile.json /app/loom_check.json \
       || ! python3 /tests/ref.py swatch /tests/visible_tile.json /app/loom_check.json; then
        echo "FAIL: /app/loom.py CLI disagrees with rule on visible tile"
        reward=0
    else
        echo "ok: /app/loom.py CLI on visible tile"
    fi
    # imported weave() on the same visible tile must also match
    if ! python3 /tests/import_check.py /app/loom.py /tests/visible_tile.json /app/loom_check.json; then
        echo "FAIL: imported weave() disagrees with rule"
        reward=0
    else
        echo "ok: imported weave() on visible tile"
    fi
fi

# --- deliverable 2: /app/swatch.json must match the rule for /app/tile.json --
if [ ! -f /app/swatch.json ]; then
    echo "FAIL: missing /app/swatch.json"
    reward=0
else
    if ! python3 /tests/ref.py swatch /app/tile.json /app/swatch.json; then
        echo "FAIL: /app/swatch.json does not match rule for /app/tile.json"
        reward=0
    else
        echo "ok: /app/swatch.json matches rule"
    fi
fi

rm -f /app/loom_check.json
echo "reward=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0
