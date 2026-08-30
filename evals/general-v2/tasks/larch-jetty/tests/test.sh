#!/bin/bash
# Meridian consolidator verifier.
# Executes the delivered /app/solve.py against the visible data in /app/data,
# then against every hidden scenario in /tests/hidden/*, grading each output
# against the reference recomputation in grader.py. Writes REWARD 1/0.
mkdir -p /logs/verifier

reward=1

# --- visible case: the shipped /app/data dataset ---------------------------
# The agent's deliverable /app/answer.json must exist and equal the reference
# recomputation of /app/data. It is what solve.sh creates by RUNNING solve.py
# on /app/data (default output path).
if [ -f /app/answer.json ] \
      && python3 /tests/grader.py /app/data /app/answer.json >/dev/null; then
    :
else
    echo "VISIBLE FAIL"
    reward=0
fi

# --- hidden cases: each is a self-contained input directory -----------------
for d in /tests/hidden/*/; do
    [ -d "$d" ] || continue
    case_name="$(basename "$d")"
    if python3 /app/solve.py "$d" "/tmp/out_${case_name}.json" \
       && python3 /tests/grader.py "$d" "/tmp/out_${case_name}.json" >/dev/null; then
        echo "HIDDEN-$case_name OK"
    else
        echo "HIDDEN-$case_name FAIL"
        reward=0
    fi
done

echo "$reward" > /logs/verifier/reward.txt
echo "REWARD=$reward"