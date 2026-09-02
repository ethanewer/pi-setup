#!/usr/bin/env bash
#
# Verifier for the "gray-market" task.
# Installs the deliverable wheel into a clean offline venv, validates its
# METADATA / entry points, and exercises the installed package and console
# script against tests/hidden/cases.json (fresh edge/malformed inputs).
#
# Always ends by writing a numeric reward to /logs/verifier/reward.txt.
set -euo pipefail

mkdir -p /logs/verifier

shopt -s nullglob
WHEELS=( /app/dist/*.whl )
shopt -u nullglob
if [ "${#WHEELS[@]}" -ne 1 ] || [ ! -f "${WHEELS[0]}" ]; then
  echo "0" > /logs/verifier/reward.txt
  echo "expected exactly one wheel in /app/dist, found ${#WHEELS[@]}" >&2
  exit 0
fi
WHEEL="${WHEELS[0]}"

# ---- build a fresh, isolated venv and install the wheel offline --------------
VENV=/tmp/vt
rm -rf "$VENV"
python3 -m venv "$VENV"
"$VENV/bin/python" -m pip install --quiet --no-index --no-deps "$WHEEL"

# ---- graded checks (hidden cases mounted at /tests/hidden) --------------------
LOG=/tmp/gray_market_verifier.log
: > "$LOG"
reward=0
if "$VENV/bin/python" /tests/checker.py "$WHEEL" /tests/hidden/cases.json > "$LOG" 2>&1; then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt
cat "$LOG" >&2
exit 0
