#!/bin/bash
# dune-notch verifier: executes the delivered /app/parse.py on the visible
# data and on every hidden input directory, and compares each resulting TSV
# byte-for-byte against the committed expectation.
set -eu
mkdir -p /logs/verifier
reward=0

if [ ! -f /app/parse.py ]; then
    echo "MISSING /app/parse.py" >&2
    echo "$reward" > /logs/verifier/reward.txt
    exit 0
fi
if [ ! -f /app/out.tsv ]; then
    echo "MISSING /app/out.tsv" >&2
    echo "$reward" > /logs/verifier/reward.txt
    exit 0
fi

# 1) Visible deliverables: shipped /app/out.tsv must equal the expectation,
#    and re-running the parser on /app/data must reproduce it.
if ! diff -q /app/out.tsv /tests/expected.tsv >/dev/null; then
    echo "VISIBLE /app/out.tsv mismatch" >&2
    echo "$reward" > /logs/verifier/reward.txt
    exit 0
fi
python3 /app/parse.py /app/data /tmp/vis.tsv
if ! diff -q /tmp/vis.tsv /tests/expected.tsv >/dev/null; then
    echo "VISIBLE parser rerun mismatch" >&2
    echo "$reward" > /logs/verifier/reward.txt
    exit 0
fi

# 2) Hidden cases: one directory per scenario.
for d in /tests/hidden/h*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    exp="/tests/hidden/${name}_expected.tsv"
    if [ ! -f "$exp" ]; then
        echo "no expectation $exp" >&2
        echo "$reward" > /logs/verifier/reward.txt
        exit 0
    fi
    python3 /app/parse.py "$d" "/tmp/$name.tsv"
    if ! diff -q "/tmp/$name.tsv" "$exp" >/dev/null; then
        echo "HIDDEN $name mismatch" >&2
        echo "$reward" > /logs/verifier/reward.txt
        exit 0
    fi
done

reward=1
echo "$reward" > /logs/verifier/reward.txt
