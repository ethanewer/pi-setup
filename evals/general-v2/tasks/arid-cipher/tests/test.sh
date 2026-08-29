#!/usr/bin/env bash
# Verifier for arid-cipher. Executes the /app/clean.py deliverable against every
# hidden input case and validates each produced artifact. Writes REWARD to
# /logs/verifier/reward.txt.
set -uo pipefail

LOGS=/logs/verifier
mkdir -p "$LOGS"
reward=0
reason=""

echo "[verifier] starting"

# ---- 0. Deliverable program must exist and be executable ------------------
if [ ! -e /app/clean.py ]; then
  echo "0" > "$LOGS/reward.txt"
  exit 0
fi

# ---- 1. Deliverable program must run and print its completion message -----
if python3 /app/clean.py /app/input /tmp/out_smpl >/tmp/run_smpl.log 2>&1; then
  if grep -q "ARID-CLOSE-OUT COMPLETE" /tmp/run_smpl.log; then
    echo "[verifier] clean.py ran on sample input and printed completion message"
  else
    echo "[verifier] FAIL: missing completion message" >&2
    echo "0" > "$LOGS/reward.txt"
    exit 0
  fi
else
  echo "[verifier] FAIL: clean.py did not exit 0 on sample input" >&2
  echo "0" > "$LOGS/reward.txt"
  exit 0
fi

# ---- 2. All declared /app deliverables must exist --------------------------
missing=0
for f in /app/result.json /app/top.tsv /app/summaries.csv \
  /app/category_lists.csv /app/contacts_filtered.csv /app/hourly.csv \
  /app/papers.jsonl /app/trials/trial_00.csv /app/trials/trial_19.csv; do
  if [ ! -s "$f" ]; then
    echo "[verifier] FAIL: deliverable $f missing/empty" >&2
    missing=1
  fi
done
if [ "$missing" -eq 1 ]; then
  echo "0" > "$LOGS/reward.txt"
  exit 0
fi
echo "[verifier] all declared /app deliverables present"

# ---- 3. Execute the deliverable on every hidden case and validate ---------
cases=()
for d in /tests/hidden/*/; do
  [ -d "$d" ] && cases+=("$d")
done

if [ "${#cases[@]}" -eq 0 ]; then
  echo "[verifier] FAIL: no hidden cases" >&2
  echo "0" > "$LOGS/reward.txt"
  exit 0
fi

all_pass=1
for d in "${cases[@]}"; do
  inp="${d%/}"
  out="/tmp/out_$(basename "$inp")"
  rm -rf "$out"
  if ! python3 /app/clean.py "$inp" "$out" >/tmp/run_case.log 2>&1; then
    echo "[verifier] FAIL: clean.py error on $(basename "$inp")" >&2
    tail -5 /tmp/run_case.log >&2
    all_pass=0
    break
  fi
  if ! grep -q "ARID-CLOSE-OUT COMPLETE" /tmp/run_case.log; then
    echo "[verifier] FAIL: no completion message on $(basename "$inp")" >&2
    all_pass=0
    break
  fi
  if ! python3 /tests/check.py "$inp" "$out"; then
    echo "[verifier] FAIL: check failed for $(basename "$inp")" >&2
    all_pass=0
    break
  fi
done

if [ "$all_pass" -eq 1 ]; then
  reward=1
  reason="all ${#cases[@]} hidden cases passed"
fi

echo "[verifier] result: REWARD=$reward ($reason)"
echo "$reward" > "$LOGS/reward.txt"
exit 0
