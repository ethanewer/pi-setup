#!/bin/bash
# Verifier for turret-moor.
# Deliverable /app/analyze.py must:
#   - be invoked as: python3 /app/analyze.py <dataset-dir> <out.json>
#   - load the dataset through yt's own API (yt.load) and compute with yt's
#     field/quantity machinery, not a hand-rolled binary parser
#   - write <out.json> with keys total_mass_g, mass_weighted_temperature_K,
#     cell_count (exactly)
# The expectation is recomputed independently with numpy (tests/expect.py)
# from the same pluto-format files.

trap 'if [ ! -f /logs/verifier/reward.txt ]; then mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; fi' EXIT
set -u
mkdir -p /logs/verifier

RTOL=1e-3
fails=""

note_fail() {
  if [ -z "$fails" ]; then
    fails="$1"
  else
    fails="$fails
$1"
  fi
}

# --- 1. the declaration that the cloned tree is the installed yt -----------
if ! python3 -c '
import sys
import yt
sys.exit(0 if yt.__file__.startswith("/app/src/") else 1)
' >/dev/null 2>&1; then
  note_fail "FAIL: installed yt is not the /app/src upstream clone (import yt -> $(python3 -c 'import yt; print(yt.__file__)' 2>/dev/null))"
fi

# --- 2. deliverable file + genuine yt usage (static) ------------------------
if [ ! -f /app/analyze.py ]; then
  note_fail "FAIL: /app/analyze.py missing"
else
  grep -q "import yt" /app/analyze.py || note_fail "FAIL: /app/analyze.py never imports yt"
  grep -q "yt\.load" /app/analyze.py || note_fail "FAIL: /app/analyze.py never calls yt.load -- reimplementing the loader is not the task"
  if ! python3 -m py_compile /app/analyze.py >/dev/null 2>&1; then
    note_fail "FAIL: /app/analyze.py does not compile"
  fi
fi

# --- 3. visible-fixture deliverable /app/answer.json ------------------------
if [ ! -f /app/answer.json ]; then
  note_fail "FAIL: /app/answer.json missing (run the analysis on /app/data/sim)"
else
  truth=$(python3 /tests/expect.py /app/data/sim 2>/dev/null) || note_fail "FAIL: couldn't compute visible expectation"
  if [ -n "$truth" ]; then
    if ! python3 /tests/compare.py "$truth" /app/answer.json "$RTOL" >/dev/null 2>&1; then
      note_fail "FAIL: /app/answer.json does not match the independently computed values for /app/data/sim"
    fi
  fi
fi

# --- 4. hidden generalization cases -----------------------------------------
if [ ! -d /tests/hidden ]; then
  note_fail "FAIL: no hidden cases present"
else
  for case_dir in /tests/hidden/*/; do
    [ -d "${case_dir}sim" ] || continue
    out_path=$(mktemp /tmp/turret-out.XXXXXX.json)
    if ! python3 /app/analyze.py "${case_dir}sim" "$out_path" >/dev/null 2>&1; then
      note_fail "FAIL: /app/analyze.py did not run on ${case_dir}sim"
      rm -f "$out_path"
      continue
    fi
    truth=$(python3 /tests/expect.py "${case_dir}sim" 2>/dev/null || true)
    if [ -z "$truth" ]; then
      note_fail "FAIL: could not compute expectation for ${case_dir}sim"
    elif ! python3 /tests/compare.py "$truth" "$out_path" "$RTOL" >/dev/null 2>&1; then
      note_fail "FAIL: output for ${case_dir}sim disagrees with the numpy expectation"
    else
      echo "OK   ${case_dir}sim"
    fi
    rm -f "$out_path"
  done
fi

# --- 5. outcome -------------------------------------------------------------
if [ -n "$fails" ]; then
  echo "VERIFIER FAILURES:"
  echo "$fails"
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

echo "VERIFIER PASS: independent numpy expectations matched on visible + all hidden datasets, yt usage asserted."
echo "1" > /logs/verifier/reward.txt
exit 0