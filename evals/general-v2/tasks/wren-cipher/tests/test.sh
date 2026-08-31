#!/bin/bash
# Verifier for wren-cipher: re-executes /app/seal.sh on the visible fixtures
# and on hidden source directories/passphrases, independently decrypts and
# diffs the extracted trees, inspects OpenPGP packet cipher/S2K hash, checks
# wrong-passphrase rejection and scans for surviving plaintext intermediates.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
W=/tmp/vrfy_wren
rm -rf "$W"; mkdir -p "$W"
fail=0
note(){ if [ "$1" = 1 ]; then echo "PASS: $2"; else echo "FAIL: $2"; fail=$((fail+1)); fi; }

scan_intermediates(){
  local found
  found=$(find /app /tmp -xdev \( -name '*.tar' -o -name '*.tar.gz' -o -name '*.tgz' \) 2>/dev/null | grep -v "^$W/" || true)
  if [ -n "$found" ]; then echo "$found"; return 1; fi
  return 0
}

decrypt_to(){
  # <gpg> <passfile> <out>
  mkdir -p "$(dirname "$3")"
  gpg --batch --yes --pinentry-mode loopback --passphrase-file "$2" \
      -o "$3" --decrypt "$1" >/dev/null 2>"$W/decrypt-last.err"
}

packets_ok(){
  # cipher 9 = AES256, s2k hash 10 = SHA512
  local out
  out=$(gpg --list-packets "$1" 2>/dev/null || true)
  printf '%s' "$out" | grep -Eq 'cipher 9' && printf '%s' "$out" | grep -Eq 'hash 10'
}

# 0. deliverables present
ok=1
[ -s /app/seal.sh ] || { ok=0; echo "missing /app/seal.sh"; }
[ -s /app/evidence.gpg ] || { ok=0; echo "missing /app/evidence.gpg"; }
[ -s /app/cipher.txt ] || { ok=0; echo "missing /app/cipher.txt"; }
note $ok "all three deliverables present and non-empty"

# 1. no plaintext intermediates before we create any of our own
if scan_intermediates; then
  note 1 "no plaintext intermediates under /app or /tmp at verify start"
else
  note 0 "plaintext intermediates found at verify start"
fi

# 2. cipher.txt names AES-256
if grep -Eiq 'aes-?256' /app/cipher.txt 2>/dev/null; then ok=1; else ok=0; echo "cipher.txt=$(cat /app/cipher.txt 2>/dev/null | head -c 40)"; fi
note $ok "cipher.txt names AES-256"

# 3. visible: re-run seal.sh (bash invocation, defaults), decrypt, diff
ok=1
bash /app/seal.sh >/dev/null 2>"$W/vis.err" || { ok=0; echo "seal.sh (bash, defaults) rc!=0: $(head -c 200 "$W/vis.err")"; }
if [ $ok = 1 ]; then
  [ -s /app/evidence.gpg ] || { ok=0; echo "seal.sh did not (re)write /app/evidence.gpg"; }
fi
if [ $ok = 1 ]; then
  if decrypt_to /app/evidence.gpg /app/.seal-key "$W/vis/snap.bin"; then :; else ok=0; echo "decrypt of /app/evidence.gpg failed"; fi
fi
if [ $ok = 1 ]; then
  mkdir -p "$W/vis/x" && tar -xf "$W/vis/snap.bin" -C "$W/vis/x" 2>/dev/null || { ok=0; echo "extract failed"; }
  diff -r /app/evidence "$W/vis/x/evidence" >/dev/null 2>&1 || { ok=0; echo "extracted tree differs from /app/evidence"; }
fi
packets_ok /app/evidence.gpg || { ok=0; echo "packets of /app/evidence.gpg missing cipher 9 / hash 10"; }
if scan_intermediates; then
  note 1 "visible seal left no plaintext intermediates"
else
  note 0 "plaintext intermediates survived visible run"
fi
note $ok "visible seal: bash-invoked seal.sh produces a decryptable AES256/SHA512 archive matching /app/evidence, no intermediates"

# 4. hidden case alpha: args + wrong passphrase must fail
ok=1
bash /app/seal.sh /tests/hidden/case_alpha/src "$W/alpha.gpg" /tests/hidden/case_alpha/key >/dev/null 2>"$W/alpha.err" \
  || { ok=0; echo "seal.sh failed on case_alpha: $(head -c 200 "$W/alpha.err")"; }
if [ $ok = 1 ]; then
  decrypt_to "$W/alpha.gpg" /tests/hidden/case_alpha/key "$W/alpha/snap.bin" || { ok=0; echo "case_alpha decrypt failed"; }
fi
if [ $ok = 1 ]; then
  mkdir -p "$W/alpha/x" && tar -xf "$W/alpha/snap.bin" -C "$W/alpha/x" 2>/dev/null || { ok=0; echo "case_alpha extract failed"; }
  diff -r /tests/hidden/case_alpha/src "$W/alpha/x/src" >/dev/null 2>&1 || { ok=0; echo "case_alpha tree mismatch"; }
  packets_ok "$W/alpha.gpg" || { ok=0; echo "case_alpha packets missing cipher 9 / hash 10"; }
  if decrypt_to "$W/alpha.gpg" /tests/hidden/case_alpha/wrongkey "$W/alpha/wrong.bin" >/dev/null 2>&1; then
    ok=0; echo "case_alpha decrypted with a WRONG passphrase"
  fi
fi
note $ok "hidden case_alpha: args-driven seal decrypts to matching tree, right packets, wrong passphrase rejected"

# 5. hidden case beta: direct-exec invocation style
ok=1
/app/seal.sh /tests/hidden/case_beta/src "$W/beta.gpg" /tests/hidden/case_beta/key >/dev/null 2>"$W/beta.err" \
  || { ok=0; echo "seal.sh (direct exec) failed on case_beta: $(head -c 200 "$W/beta.err")"; }
if [ $ok = 1 ]; then
  decrypt_to "$W/beta.gpg" /tests/hidden/case_beta/key "$W/beta/snap.bin" || { ok=0; echo "case_beta decrypt failed"; }
  mkdir -p "$W/beta/x" && tar -xf "$W/beta/snap.bin" -C "$W/beta/x" 2>/dev/null || { ok=0; echo "case_beta extract failed"; }
  diff -r /tests/hidden/case_beta/src "$W/beta/x/src" >/dev/null 2>&1 || { ok=0; echo "case_beta tree mismatch"; }
  packets_ok "$W/beta.gpg" || { ok=0; echo "case_beta packets missing cipher 9 / hash 10"; }
fi
note $ok "hidden case_beta: direct-exec seal.sh decrypts to matching tree with right packets"

# 6. final intermediates sweep (exclude the verifier's own work dir)
if scan_intermediates; then
  note 1 "final sweep: no plaintext intermediates under /app or /tmp"
else
  note 0 "final sweep: plaintext intermediates survived"
fi

# cleanup verifier artifacts so the sweep result stands for re-reads
rm -rf "$W"

if [ "$fail" = 0 ]; then echo 1 > /logs/verifier/reward.txt; else echo 0 > /logs/verifier/reward.txt; fi
echo "VERIFIER_COMPLETE failures=$fail reward=$(cat /logs/verifier/reward.txt)"
exit 0
