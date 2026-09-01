#!/bin/bash
# larch-hearth verifier (tests/test.sh).
#
# Re-executes the deliverable /app/run.sh on the main scenario and on every
# hidden scenario in /tests/hidden, then validates each produced guest.iso +
# serial.log + guest.prog.exit with tests/validate.py against the scenario.
# Always ends by writing a numeric reward to /logs/verifier/reward.txt.
set -u

fail() { echo 0 > /logs/verifier/reward.txt; echo "VERIFIER FAIL: $1"; exit 0; }

[ -x /app/run.sh ] || fail "no executable /app/run.sh (pristine container)"
MAIN="/app/scenario-main.json"
[ -f "$MAIN" ] || fail "no /app/scenario-main.json"

run_and_check() {
  local scn="$1" out="$2"
  if [ "$out" != "/app" ]; then
    rm -rf "$out"; mkdir -p "$out"
  fi
  bash /app/run.sh "$scn" "$out" || fail "run.sh returned nonzero for $scn"
  python3 /tests/validate.py "$out" "$scn" || fail "validation failed for $scn"
  echo "  verified: $(basename "$scn")"
}

# 1) main scenario -> /app (the deliverables live here)
run_and_check "$MAIN" "/app"

# 2) hidden scenarios -> per-case outdirs
i=0
for scn in /tests/hidden/*.json; do
  [ -f "$scn" ] || continue
  i=$((i + 1))
  run_and_check "$scn" "/tmp/larch_out_h$i"
done
[ "$i" -ge 2 ] || fail "expected at least 2 hidden scenarios, got $i"

echo 1 > /logs/verifier/reward.txt
echo "VERIFIER PASS: main + $i hidden scenarios"
