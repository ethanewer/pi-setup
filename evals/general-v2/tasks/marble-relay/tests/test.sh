#!/usr/bin/env bash
# marble-relay verifier (executes-deliverable).
# Drives the deliverables (/app/relay.json manifest + /app/bin/relay binary)
# through the shipped external launcher (/app/launcher.js) on hidden cases and
# requires the BOOT_OK / FRAME_OK / ALL_OK stdout contract. Writes reward to
# /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=1
fail(){ echo "FAIL: $*" >&2; reward=0; }

# ---- manifest deliverable ------------------------------------------------ #
if [ ! -f /app/relay.json ]; then
  fail "missing /app/relay.json (launcher cannot discover the entrypoint)"
else
  entry=$(python3 -c 'import json;print(json.load(open("/app/relay.json")).get("entry",""))' 2>/dev/null || true)
  [ "$entry" = "/app/bin/relay" ] || fail "relay.json entry '$entry' != /app/bin/relay"
fi

# ---- binary deliverable: present, executable, native ELF ------------------ #
[ -x /app/bin/relay ] || fail "missing/not executable /app/bin/relay"
if [ -x /app/bin/relay ] && command -v file >/dev/null 2>&1; then
  file -b /app/bin/relay | grep -q ELF || fail "/app/bin/relay is not a native ELF binary"
fi
[ "$reward" -eq 0 ] && { echo "0" > /logs/verifier/reward.txt; echo "final-reward=0"; exit 0; }

# ---- boot + frame contract via the external launcher, hidden cases -------- #
shopt -s nullglob
cases=(/tests/hidden/*.json)
shopt -u nullglob
[ ${#cases[@]} -gt 0 ] || fail "no hidden case files under /tests/hidden"
for c in "${cases[@]}"; do
  out=$(timeout 120 node /app/launcher.js "$c" 2>/dev/null)
  rc=$?
  if [ "$rc" -eq 124 ]; then fail "$c: launcher timed out"; continue; fi
  echo "$out" | grep -q '^BOOT_OK$'  || fail "$c: no BOOT_OK (rc=$rc): $(echo "$out" | head -1)"
  echo "$out" | grep -q '^ALL_OK$'   || fail "$c: no ALL_OK (rc=$rc)"
  if echo "$out" | grep -qE 'BOOT_FAIL|FRAME_FAIL|ALL_FAIL'; then
    fail "$c: failure marker present: $(echo "$out" | grep -E 'FAIL' | head -2)"
  fi
done

echo "final-reward=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0
