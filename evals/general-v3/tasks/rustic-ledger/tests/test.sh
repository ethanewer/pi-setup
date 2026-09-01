#!/bin/bash
# Verifier: executes the deliverable program /app/audit.py on the visible case
# and on every hidden case, and compares each report to its expected JSON.
mkdir -p /logs/verifier
reward=0
OUTDIR=/tmp/verify_out
rm -rf "$OUTDIR"; mkdir -p "$OUTDIR"

if [ ! -f /app/audit.py ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

check_case() {
    # $1 store dir, $2 expected json, $3 output name
    local store=$1 want=$2 name=$3 out="$OUTDIR/$name.json"
    if ! python3 /app/audit.py "$store" "$out"; then
        echo "case $name: audit.py failed" >&2
        return 1
    fi
    python3 - "$out" "$want" <<'PY'
import json, sys
with open(sys.argv[1]) as f: got = json.load(f)
with open(sys.argv[2]) as f: want = json.load(f)
assert set(got) == set(want), ("keys", set(got), set(want))
for k in want:
    assert sorted(got[k]) == sorted(want[k]), (k, got[k], want[k])
PY
}

ok=1

# --- visible case -------------------------------------------------------
if ! check_case /app/store /tests/expected.json visible; then
    echo "visible case mismatch" >&2; ok=0
fi
# deliverable sanity output must also be present and match a fresh run
if [ ! -f /app/audit.json ]; then
    echo "/app/audit.json missing" >&2; ok=0
fi

# --- hidden cases -------------------------------------------------------
for case_dir in /tests/hidden/*; do
    [ -d "$case_dir" ] || continue
    name=$(basename "$case_dir")
    if ! check_case "$case_dir/store" "$case_dir/expected.json" "$name"; then
        echo "hidden case $name failed" >&2; ok=0
    fi
done

# --- no-modify guard: the shipped store must be unchanged -----------------
store_state() { ( cd /app/store && find . -type f -print0 | sort -z | xargs -0 sha256sum ); }
before=$(store_state)
python3 /app/audit.py /app/store "$OUTDIR/_guard.json" || ok=0
after=$(store_state)
[ "$before" = "$after" ] || { echo "store was modified" >&2; ok=0; }

[ "$ok" = "1" ] && reward=1
echo "$reward" > /logs/verifier/reward.txt