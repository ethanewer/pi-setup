#!/usr/bin/env bash
# Verifier for raven-anchor. Executes the /app/clean.py deliverable against the
# hidden input cases and validates every produced artifact against an independent
# recomputation. Also requires the literal /app deliverables to be present and
# matching when clean.py is (re)run on a copy of the visible fixtures.
# Writes the numeric reward to /logs/verifier/reward.txt.
set -uo pipefail

LOGS=/logs/verifier
mkdir -p "$LOGS"
reward=0
reason=""

echo "[verifier] raven-anchor starting"

# ---- 0. Deliverable program must exist and be executable ------------------
if [ ! -e /app/clean.py ]; then
  echo "[verifier] FAIL: /app/clean.py missing" >&2
  echo "0" > "$LOGS/reward.txt"
  exit 0
fi

# ---- 1. literal /app deliverables must exist ------------------------------
for f in /app/aggregated.csv /app/summary.csv /app/result.json \
         /app/projects_grouped.csv /app/filtered.csv /app/top.tsv \
         /app/series_filled.csv /app/papers.jsonl; do
  if [ ! -s "$f" ]; then
    echo "[verifier] FAIL: literal deliverable $f missing/empty" >&2
    echo "0" > "$LOGS/reward.txt"
    exit 0
  fi
done
echo "[verifier] literal /app deliverable files present"

# ---- 2. run clean.py on the visible fixtures -> must equal expected -------
rm -rf /tmp/lit_out
if ! python3 /app/clean.py /app/data /tmp/lit_out >/tmp/lit.log 2>&1; then
  echo "[verifier] FAIL: clean.py error on visible fixtures" >&2
  tail -5 /tmp/lit.log >&2
  echo "0" > "$LOGS/reward.txt"
  exit 0
fi
if ! grep -q "RAVEN-CLOSE-OUT COMPLETE: STATUS=OK" /tmp/lit.log; then
  echo "[verifier] FAIL: missing completion line" >&2
  echo "0" > "$LOGS/reward.txt"
  exit 0
fi
# literal /app outputs should match the freshly recomputed ones from /app/data
if ! python3 /tests/check.py /app/data /app >/tmp/check_lit.log 2>&1; then
  echo "[verifier] FAIL: literal /app outputs did not match reference (visible)" >&2
  tail -30 /tmp/check_lit.log >&2
  echo "0" > "$LOGS/reward.txt"
  exit 0
fi
echo "[verifier] visible/literal outputs matched reference"

# ---- 3. execute clean.py on every hidden case and validate ----------------
cases=()
for d in /tests/hidden/*/data; do
  [ -d "$d" ] && cases+=("$d")
done
if [ "${#cases[@]}" -eq 0 ]; then
  echo "[verifier] FAIL: no hidden cases present" >&2
  echo "0" > "$LOGS/reward.txt"
  exit 0
fi

all_pass=1
for d in "${cases[@]}"; do
  key=$(basename "$(dirname "$d")")
  out="/tmp/out_$key"
  rm -rf "$out"
  if ! python3 /app/clean.py "$d" "$out" >/tmp/run_case.log 2>&1; then
    echo "[verifier] FAIL: clean.py error on $key" >&2
    tail -5 /tmp/run_case.log >&2
    all_pass=0
    break
  fi
  if ! python3 /tests/check.py "$d" "$out" >/tmp/check_case.log 2>&1; then
    echo "[verifier] FAIL: hidden case $key mismatch" >&2
    tail -40 /tmp/check_case.log >&2
    all_pass=0
    break
  fi
done

if [ "$all_pass" -eq 1 ]; then
  reward=1
  reason="literal outputs + all ${#cases[@]} hidden cases passed"
fi
echo "[verifier] result: REWARD=$reward ($reason)"
echo "$reward" > "$LOGS/reward.txt"
exit 0