#!/bin/bash
# Verifier for golden-braid: executes the assembled deliverable program
# on the visible case and on hidden cases, comparing exact single-line output.
mkdir -p /logs/verifier
reward=0

work=/tmp/gb_verify
rm -rf "$work"; mkdir -p "$work"
PY=/app/solve.py

fail() { echo "VERIFY FAIL: $1" >&2; }

if [ ! -f "$PY" ]; then
    fail "deliverable $PY not present"
    echo "$reward" > /logs/verifier/reward.txt
    exit 0
fi

run_case() {
    # run_case <input.fa> <expected.txt> <label>
    local input="$1" expected="$2" label="$3" out="$work/out.$label"
    if ! python3 "$PY" "$input" "$out" >"$work/stderr.$label" 2>&1; then
        fail "$label: script exited non-zero"
        return 1
    fi
    if ! cmp -s "$expected" "$out"; then
        fail "$label: output mismatch"
        printf '  expected: ' >&2; cat "$expected" >&2
        printf '  got:      ' >&2; cat "$out" >&2
        return 1
    fi
    return 0
}

all_ok=1

# --- deliverable /app/contig.txt (visible case output file) ---
# The instruction requires the agent to leave /app/contig.txt as the result of
# running /app/solve.py on /app/reads.txt. Verify it exists and matches the
# visible-case expectation exactly.
if [ -f /app/contig.txt ]; then
    if ! cmp -s /tests/expected.txt /app/contig.txt; then
        fail "deliverable /app/contig.txt mismatch"
        all_ok=0
    fi
else
    fail "deliverable /app/contig.txt not present"
    all_ok=0
fi

# --- visible case (running solve.py independently on the visible input) ---
if [ -f /app/reads.txt ] && [ -f /tests/expected.txt ]; then
    run_case /app/reads.txt /tests/expected.txt visible || all_ok=0
else
    fail "missing visible case files"
    all_ok=0
fi

# --- hidden cases ---
if [ -d /tests/hidden ]; then
    for exp in /tests/hidden/*.out; do
        [ -e "$exp" ] || continue
        base="${exp%.out}"
        fa="$base.fa"
        [ -f "$fa" ] || { fail "missing input for $base"; all_ok=0; continue; }
        label="$(basename "$base")"
        out="$work/out.$label"
        run_case "$fa" "$exp" "$label" || all_ok=0
    done
else
    fail "no /tests/hidden directory"
    all_ok=0
fi

[ "$all_ok" = 1 ] && reward=1

echo "$reward" > /logs/verifier/reward.txt
echo "golden-braid verifier reward=$reward" >&2
exit 0