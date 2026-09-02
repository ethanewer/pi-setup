#!/bin/bash
# Verifier for the quiet-bridge telemetry decoder task.
# Runs /app/decode.py on a visible sample and several hidden inputs,
# then compares each output JSON to its expected JSON.
set -u
mkdir -p /logs/verifier
reward=0
DELIVERABLE=/app/decode.py
VISIBLE_IN=/app/stream.hex
VISIBLE_EXP=/tests/expected.json
HIDDEN_DIR=/tests/hidden

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

ok=1  # assume success, unset on any failure

run() {
  local inp="$1" exp="$2"
  local out="$work/out_$(basename "$inp").json"
  if ! python3 "$DELIVERABLE" "$inp" "$out" >/dev/null 2>&1; then
    echo "FIELD: decoder failed to run on $inp" >&2
    ok=0
    return
  fi
  python3 - "$out" "$exp" <<'PY'
import json, sys
got = json.load(open(sys.argv[1]))
exp = json.load(open(sys.argv[2]))
assert got == exp, (got, exp)
PY
  if [ $? -ne 0 ]; then
    echo "FIELD: output mismatch on $inp" >&2
    ok=0
  fi
}

if [ ! -f "$DELIVERABLE" ]; then
  echo "FIELD: $DELIVERABLE missing" >&2
  echo "$reward" > /logs/verifier/reward.txt
  exit 0
fi

# 1) Visible sample
run "$VISIBLE_IN" "$VISIBLE_EXP"

# 2) Hidden cases
if [ -d "$HIDDEN_DIR" ]; then
  for hex in "$HIDDEN_DIR"/*.hex; do
    [ -e "$hex" ] || continue
    exp="${hex%.hex}.expected.json"
    if [ -f "$exp" ]; then
      run "$hex" "$exp"
    fi
  done
fi

[ "$ok" -eq 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0