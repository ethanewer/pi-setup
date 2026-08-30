#!/usr/bin/env bash
# Verifier for echo-dial. Executes the /app/attack.py deliverable against the
# visible relay and every hidden input directory, validating each artifact with
# the independent tests/check.py. Writes REWARD to /logs/verifier/reward.txt.
set -uo pipefail

LOGS=/logs/verifier
mkdir -p "$LOGS"

fail() {
  echo "0" > "$LOGS/reward.txt"
  exit 0
}

echo "[verifier] starting echo-dial"

# ---- 0. Deliverable must exist ----------------------------------------------
# The instruction invokes the deliverable as `python3 /app/attack.py`, so it
# must be a readable Python source file; no executable bit is required.
[ -f /app/attack.py ] || { echo "[verifier] FAIL: /app/attack.py missing" >&2; fail; }
[ -f /tests/check.py ] || { echo "[verifier] FAIL: check.py not mounted" >&2; fail; }

# ---- 1. Deliverables /app/name.txt, plaintexts.txt, word.txt exist ---------
[ -s /app/name.txt ] && [ -s /app/plaintexts.txt ] && [ -s /app/word.txt ] || {
  echo "[verifier] FAIL: one of /app deliverable artifacts missing" >&2; fail; }
echo "[verifier] /app artifacts present"

# ---- 2. Validate the /app deliverables against the visible expectation ------
if ! python3 /tests/check.py /app /tests/expected.json; then
  echo "[verifier] FAIL: visible /app deliverables do not match expectation" >&2
  fail
fi
echo "[verifier] visible /app deliverables match"

# ---- 3. Re-execute the deliverable on a fresh clone of the visible relay ----
rm -rf /tmp/vis
if ! python3 /app/attack.py /app/relay /tmp/vis >/tmp/vis.log 2>&1; then
  echo "[verifier] FAIL: attack.py did not exit 0 on /app/relay" >&2
  tail -5 /tmp/vis.log >&2
  fail
fi
if ! python3 /tests/check.py /tmp/vis /tests/expected.json; then
  echo "[verifier] FAIL: re-run of attack.py on visible relay mismatched" >&2
  fail
fi
echo "[verifier] attack.py re-run matches visible expectation"

# ---- 4. Execute the deliverable on every hidden case and validate ----------
cases=()
for d in /tests/hidden/*/; do
  [ -d "$d" ] && cases+=("$d")
done
if [ "${#cases[@]}" -eq 0 ]; then
  echo "[verifier] FAIL: no hidden cases" >&2
  fail
fi

all_pass=1
for d in "${cases[@]}"; do
  base="$(basename "$d")"
  inp="${d%/}/input"
  out="/tmp/out_$base"
  rm -rf "$out"
  if ! python3 /app/attack.py "$inp" "$out" >/tmp/run_case.log 2>&1; then
    echo "[verifier] FAIL: attack.py error on hidden/$base" >&2
    tail -5 /tmp/run_case.log >&2
    all_pass=0; break
  fi
  if ! python3 /tests/check.py "$out" "${d%/}/expected.json"; then
    echo "[verifier] FAIL: check failed for hidden/$base" >&2
    all_pass=0; break
  fi
  echo "[verifier] hidden/$base OK"
done

if [ "$all_pass" -eq 1 ]; then
  reward=1
  reason="all ${#cases[@]} hidden cases + visible passed"
else
  reward=0
  reason="some check failed"
fi

echo "[verifier] result: REWARD=$reward ($reason)"
echo "$reward" > "$LOGS/reward.txt"
exit 0
