#!/bin/bash
# Verifier for lumen-model: executes the deliverable /app/infer.py on the
# visible case and on hidden generalization cases, then requires a non-zero
# exit with no output written on malformed inputs. Writes a numeric reward
# to /logs/verifier/reward.txt.
set -eu

REWARD=0
mkdir -p /logs/verifier
INFER=/app/infer.py
HIDDEN=/tests/hidden
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; }

check_case() { # $1 = dir with model.json,input.json,expected.json
    local dir="$1"
    if [ ! -f "$dir/model.json" ] || [ ! -f "$dir/input.json" ] || [ ! -f "$dir/expected.json" ]; then
        fail "incomplete case dir $dir"; return 1
    fi
    local out="$WORK/out_$(basename "$dir").json"
    if ! python3 "$INFER" "$dir/model.json" "$dir/input.json" "$out" 2>/dev/null; then
        fail "case $(basename "$dir") non-zero exit"; return 1
    fi
    python3 - "$out" "$dir/expected.json" <<'PY' || { fail "case $(basename "$dir") mismatch"; return 1; }
import json, sys
got = json.load(open(sys.argv[1]))
want = json.load(open(sys.argv[2]))
assert set(got.keys()) == set(want.keys()), (got, want)
assert got["labels"] == want["labels"], (got, want)
assert all(isinstance(v, int) for v in got["labels"]), got
PY
}

expect_error() { # $1=model $2=input : must exit non-zero and write nothing
    local model="$1" input="$2" out="$WORK/err.json"
    rm -f "$out"
    if python3 "$INFER" "$model" "$input" "$out" 2>/dev/null; then
        fail "bad-fixture $(basename "$input") succeeded but must fail"; return 1
    fi
    if [ -e "$out" ]; then
        fail "bad-fixture $(basename "$input") wrote output despite error"; return 1
    fi
    return 0
}

ok=1

# 1. Visible case (fixtures at /app, expected at /tests/expected.json).
visible_out="$WORK/visible.json"
if ! python3 "$INFER" /app/model.json /app/vectors.json "$visible_out" 2>/dev/null; then
    fail "visible case non-zero exit"; ok=0
elif ! python3 - "$visible_out" /tests/expected.json <<'PY'
import json, sys
got = json.load(open(sys.argv[1]))
want = json.load(open(sys.argv[2]))
assert got == want, (got, want)
PY
then
    fail "visible case labels mismatch"; ok=0
fi

# 2. Hidden generalization cases.
for dir in "$HIDDEN"/case*/; do
    if [ -d "$dir" ] && ! check_case "${dir%/}"; then ok=0; fi
done

# 3. Malformed inputs must be rejected.
for ed in "$HIDDEN"/errors/*/; do
    if [ -d "$ed" ] && ! expect_error "${ed}model.json" "${ed}input.json"; then ok=0; fi
done

if [ "$ok" = 1 ]; then REWARD=1; fi
echo "$REWARD" > /logs/verifier/reward.txt
exit 0