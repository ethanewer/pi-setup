#!/bin/bash
# Verifier for elm-keystone. EXECUTES the deliverable /app/solve.py on the
# committed input and on every hidden input in /tests/hidden, then compares each
# artifact pack (plan_records.csv, decisions.txt, objective.txt,
# final_report.csv, transformed/*.csv, answer.json, schedule.xlsx) against a
# canonical reference generated from the same input by /tests/reference.py.
# Also requires the deliverable /app/answer.json to exist in the workspace.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0
PY=python3
AGENT=/app/solve.py
REF=/tmp/reference.py
cp /tests/reference.py "$REF"
chmod +x "$REF"
all=1

# Run one case: label, input csv -> output/expected dirs, compare artifacts.
run_case() {
    local label="$1" input="$2" out="$3" exp="$4" tag="$1"
    tag="$(echo "$label" | tr '/' '_')"
    rm -rf "$out" "$exp"
    if [ ! -f "$AGENT" ]; then
        echo "FAIL[$label]: $AGENT missing"; return 1; fi
    if ! "$PY" "$AGENT" --input "$input" --output "$out" >/tmp/run_${tag}.log 2>&1; then
        echo "FAIL[$label]: solve.py exit!=0: $(tail -2 /tmp/run_${tag}.log | tr '\n' ' ')"; return 1; fi
    if ! "$PY" "$REF" gen "$input" "$exp" >/tmp/gen_${tag}.log 2>&1; then
        echo "FAIL[$label]: ref-gen errored"; return 1; fi
    if ! "$PY" "$REF" cmp "$out" "$exp" >/tmp/cmp_${tag}.log 2>&1; then
        echo "FAIL[$label]: artifact mismatch:"; cat /tmp/cmp_${tag}.log; return 1; fi
    echo "OK[$label]"
    return 0
}

run_case visible /opt/keystone/requests.csv /tmp/vis_out /tmp/vis_exp || all=0

if [ ! -f /app/answer.json ]; then
    echo "FAIL: deliverable /app/answer.json missing"
    all=0
fi

if [ -d /tests/hidden ]; then
    cnt=0
    for c in $(ls /tests/hidden); do
        input="/tests/hidden/$c/requests.csv"
        [ -f "$input" ] || { echo "FAIL[hidden/$c]: missing requests.csv"; all=0; continue; }
        run_case "hidden/$c" "$input" "/tmp/out_$c" "/tmp/exp_$c" || all=0
        cnt=$((cnt+1))
    done
    [ "$cnt" -ge 2 ] || { echo "FAIL: fewer than 2 hidden cases"; all=0; }
else
    echo "FAIL: no /tests/hidden directory"
    all=0
fi

[ "$all" -eq 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
exit 0