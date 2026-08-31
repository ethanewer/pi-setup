#!/bin/bash
# cinder-hearth verifier (tests/test.sh).
#
# Re-executes the deliverable pair (mkinit.sh + console_drive.py) on the main
# scenario and on every hidden scenario, then validates each produced
# initramfs + session log with tests/validate.py. Always ends by writing a
# numeric reward to /logs/verifier/reward.txt.
set -u

fail() { echo 0.0 > /logs/verifier/reward.txt; echo "VERIFIER FAIL: $1"; exit 0; }

mkdir -p /logs/verifier

[ -x /app/mkinit.sh ] || fail "no executable /app/mkinit.sh"
[ -f /app/console_drive.py ] || fail "no /app/console_drive.py"
[ -f /app/vmlinuz ] || fail "no /app/vmlinuz"
[ -f /app/base-initrd.cpio.gz ] || fail "no /app/base-initrd.cpio.gz"
MAIN="/app/scenario-main.json"
[ -f "$MAIN" ] || fail "no /app/scenario-main.json"

run_and_check() {
  local scn="$1" out="$2"
  rm -rf "$out"; mkdir -p "$out"
  bash /app/mkinit.sh "$scn" "$out/guest-initrd.cpio.gz" || fail "mkinit.sh failed for $scn"
  [ -s "$out/guest-initrd.cpio.gz" ] || fail "empty initramfs for $scn"
  python3 /app/console_drive.py "$out/guest-initrd.cpio.gz" "$scn" "$out/session.log" \
    || fail "console_drive.py failed for $scn"
  [ -s "$out/session.log" ] || fail "empty session log for $scn"
  python3 /tests/validate.py "$out" "$scn" || fail "validation failed for $scn"
  echo "  verified: $(basename "$scn")"
}

# 0) the main-scenario deliverables the agent left in /app must be present
[ -s /app/guest-initrd.cpio.gz ] || fail "missing /app/guest-initrd.cpio.gz"
[ -s /app/session.log ] || fail "missing /app/session.log"
python3 /tests/validate.py /app "$MAIN" \
  || fail "main-scenario deliverables in /app are invalid"

# 1) main scenario: re-execute the deliverables end to end
run_and_check "$MAIN" "/tmp/cinder_out_main"

# 2) hidden scenarios
i=0
for scn in /tests/hidden/*.json; do
  [ -f "$scn" ] || continue
  i=$((i + 1))
  run_and_check "$scn" "/tmp/cinder_out_h$i"
done
[ "$i" -ge 2 ] || fail "expected at least 2 hidden scenarios, got $i"

echo 1.0 > /logs/verifier/reward.txt
echo "VERIFIER PASS: main + $i hidden scenarios"
