#!/usr/bin/env bash
# Verifier for sage-wharf (Grimwater Docks forensic reconstruction).
# Runs as root after the agent finishes; /tests is mounted read-only.
# Must produce a numeric reward in /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
E=/app
H=/tests/hidden
pass=0
total=0
fail(){ echo "FAIL: $*"; }

# --- deliverable presence ---
total=$((total+1))
if [ -f /app/solve.py ]; then pass=$((pass+1)); else fail "solve.py missing"; fi

# --- answer.json matches reference ---
total=$((total+1))
if python3 - <<'PY'
import json,sys
try:
    a=json.load(open('/app/answer.json'))
    e=json.load(open('/tests/expected.json'))
    for k in ("log_plaintext_hex","secret","wal_transform","digest","sentinel_commands"):
        if a.get(k)!=e.get(k):
            print("answer",k,"mismatch: got",a.get(k),"exp",e.get(k)); raise SystemExit(1)
    print("answer.json OK")
except SystemExit:
    sys.exit(1)
except Exception as ex:
    print("answer.json exception:",ex); sys.exit(1)
PY
then pass=$((pass+1)); else fail "answer.json mismatch"; fi

# --- range decode hidden blobs (byte-exact) ---
for b in blob1 blob2 blob3 blob_empty; do
  total=$((total+1))
  if python3 /app/solve.py decode "$H/$b.rd" > /tmp/o.bin 2>/dev/null \
     && cmp -s /tmp/o.bin "$H/$b.pt"; then
     pass=$((pass+1))
  else fail "decode $b"; fi
done

# --- round-trip: encode then decode must restore the original bytes ---
total=$((total+1))
if python3 /app/solve.py encode "$H/roundtrip.bin" > /tmp/rt.rd 2>/dev/null \
   && python3 /app/solve.py decode /tmp/rt.rd > /tmp/rt.pt 2>/dev/null \
   && cmp -s /tmp/rt.pt "$H/roundtrip.bin"; then
  pass=$((pass+1))
else fail "roundtrip (encoder must invert decoder exactly)"; fi

# --- unobfuscate hidden command payloads ---
for p in pay1 pay2 pay3; do
  total=$((total+1))
  got=$(python3 /app/solve.py unobfuscate "$H/$p.bin" 2>/dev/null)
  exp=$(cat "$H/$p.cmd")
  if [ "$got" = "$exp" ]; then pass=$((pass+1)); else fail "unobfuscate $p (got '$got')"; fi
done

# --- WAL transform detection ---
declare -A WEXP=( [wal_good.bin]="NONE" [wal_xor.bin]="KEY=93" [wal_short.bin]="NONE" [wal_noise.bin]="NONE" )
for f in wal_good.bin wal_xor.bin wal_short.bin wal_noise.bin; do
  total=$((total+1))
  got=$(python3 /app/solve.py wal-report "$H/$f" 2>/dev/null)
  if [ "$got" = "${WEXP[$f]}" ]; then pass=$((pass+1)); else fail "wal $f (got '$got' exp '${WEXP[$f]}')"; fi
done

# --- digest chain over hidden binary input ---
total=$((total+1))
got=$(python3 /app/solve.py digest "$H/digest_in.bin" 2>/dev/null)
exp=$(cat "$H/digest_out.txt")
if [ "$got" = "$exp" ]; then pass=$((pass+1)); else fail "digest (got '$got')"; fi

echo "sage-wharf verifier: pass=$pass total=$total"
reward=0
if [ "$total" -gt 0 ] && [ "$pass" = "$total" ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
echo "REWARD=$reward"
