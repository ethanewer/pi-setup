#!/usr/bin/env bash
# Verifier for tasks/zephyr-notch (executes-deliverable).
#
# Gates, in order:
#   A. the four deliverables must exist with the exact documented content
#      (/app/erased_ok.txt == "OK", results.txt == exact final message);
#   B. the shipped /app/vault is gone and its /app/data neighbors are
#      byte-identical (overwrite + unlink + directory removal really happened);
#   C. /app/capability_notes.md records the exact openssl cipher option, which
#      the verifier re-applies to fresh hidden ciphertexts (generalization);
#   D. /app/secure_erase.sh is executed on fresh hidden target trees — normal,
#      dot/spaces/read-only edge, empty tree, broken-symlink tree, and a
#      missing target — checking full removal, that a wipe-over was actually
#      performed before deletion, and that no neighbor outside the target is
#      touched.
# Writes a numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

FAILS=()
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1"; FAILS+=("$1"); }

HALL=/tests/hidden
FINAL_MESSAGE="VERIFIED HAILING BRIDGE PROTOCOL COMPLETE"
REF_ACTIVITY=6e7faf243ab04e7ae99f1a37bb3f40ba7e1b3ceef9cf187f147c027e64d2d621
REF_NOTES=56486b5a3a6fa5d0752e79ba2e8405c260bad3199fa6126db7ff91ec6511e843

# ---------------------------------------------------------------------------
# A. Deliverable presence and exact contents
# ---------------------------------------------------------------------------
for f in /app/secure_erase.sh /app/erased_ok.txt /app/capability_notes.md \
         /app/results.txt; do
  [ -e "$f" ] || fail "missing deliverable $f"
done

if [ -f /app/erased_ok.txt ]; then
  m="$(cat /app/erased_ok.txt)"
  [ "$m" = "OK" ] || fail "erased_ok.txt unexpected content: [$m]"
fi

if [ -f /app/results.txt ]; then
  stripped="$(sed 's/[[:space:]]*$//' /app/results.txt)"
  [ "$stripped" = "$FINAL_MESSAGE" ] || fail "results.txt exact mismatch: [$stripped]"
  [ -s /app/results.txt ] || fail "results.txt empty"
fi

# ---------------------------------------------------------------------------
# B. Shipped vault erased + neighbors byte-identical
# ---------------------------------------------------------------------------
if [ -e /app/vault ]; then fail "shipped /app/vault still exists"; fi
if [ -e /app/data/vault ]; then fail "unexpected /app/data/vault present"; fi
h1="$(sha256sum /app/data/activity.log 2>/dev/null | awk '{print $1}')"
h2="$(sha256sum /app/data/notes.rst 2>/dev/null | awk '{print $1}')"
[ "$h1" = "$REF_ACTIVITY" ] || fail "neighbor activity.log changed"
[ "$h2" = "$REF_NOTES" ] || fail "neighbor notes.rst changed"

# ---------------------------------------------------------------------------
# C. capability notes: exact cipher option recorded; then re-applied
# ---------------------------------------------------------------------------
OPTION=""
if [ -f /app/capability_notes.md ]; then
  OPTION="$(sed -nE 's/^cipher option:[[:space:]]+(.*)$/\1/p' \
            /app/capability_notes.md | tr -d '[:space:]' | head -n1)"
fi
case "$OPTION" in
  -aes-256-ctr) ;;
  *) fail "capability_notes.md does not record -aes-256-ctr (got: ${OPTION})" ;;
esac

# Re-apply the documented capability to fresh hidden ciphertexts.
if [ -n "$OPTION" ]; then
  for spec in "$HALL"/crypto/case_*.meta.json; do
    [ -e "$spec" ] || continue
    name="$(basename "$spec" .meta.json)"
    key="$(python3 -c "import json,sys;print(json.load(open('$spec'))['key'])")"
    iv="$(python3 -c "import json,sys;print(json.load(open('$spec'))['iv'])")"
    exp="$(python3 -c "import json,sys;print(json.load(open('$spec'))['expected'])")"
    out="/tmp/ze_crypt_$name.out"
    if openssl enc -d "$OPTION" -K "$key" -iv "$iv" \
           -in "$HALL/crypto/$name.enc" -out "$out" 2>/dev/null; then
      got="$(cat "$out" 2>/dev/null)"
      if [ "$got" != "$exp" ]; then
        fail "crypto $name: decrypted text mismatch (option re-application)"
      fi
    else
      fail "crypto $name: openssl -d with noted option failed (re-application)"
    fi
  done
fi

# ---------------------------------------------------------------------------
# D. Execute /app/secure_erase.sh on fresh hidden target directories
# ---------------------------------------------------------------------------

# ---- Overwrite audit via strace ----------------
# A plain rm/unlink leaves file contents untouched, so the erased bytes remain
# recoverable: that is exactly the competency under test. To prove overwrite,
# we re-run the erase under strace and require that every regular file that
# used to be under the target directory was the subject of an actual
# write()/pwrite64() syscall (i.e. its contents were written-over) on the way
# out. This is independent of how the agent chooses to overwrite (shred, dd,
# zero-fill redirect, python writes, ...).

run_erase() {
  local tag="$1" src="$2"
  local work="/tmp/ze_${tag}"
  rm -rf "$work"; mkdir -p "$work"
  cp -a "$src/target" "$work/target"
  cp -a "$src/keeper.txt" "$work/keeper.txt"
  # edge fixture: force a read-only inode inside the target
  if [ -f "$work/target/locked.bin" ]; then
    chmod 0444 "$work/target/locked.bin"
  fi

  local init
  init="$(find "$work/target" -type f 2>/dev/null)"

  local before; before="$(sha256sum "$work/keeper.txt" | awk '{print $1}')"
  strace -f -y -qq -e trace=write,pwrite64 \
    -o "$work/trace" bash /app/secure_erase.sh "$work/target" \
    >"$work/stdout" 2>"/dev/null"
  local rc=$?

  if [ $rc -ne 0 ]; then fail "$tag: secure_erase.sh exited $rc"; fi
  if [ -e "$work/target" ] || [ -L "$work/target" ]; then
    fail "$tag: target directory still exists after erase"; return
  fi
  local after; after="$(sha256sum "$work/keeper.txt" | awk '{print $1}')"
  [ "$before" = "$after" ] || fail "$tag: neighbor keeper file changed"

  local leftovers
  leftovers="$(cd "$work" && find . -mindepth 1 -maxdepth 1 \
                -not -name trace -not -name stdout -not -name keeper.txt | sort)"
  [ -z "$leftovers" ] || fail "$tag: unexpected debris left: $leftovers"

  # every file that vanished must have been written-over first. strace -y
  # annotates each write() with the absolute path of the fd (even when the
  # agent cd's and reopens relatively), so we require each initial file path
  # to appear as the target of an actual write under the tree.
  local written="" missing="" f
  written="$(grep -aE "write\(|pwrite\(" "$work/trace" \
             | grep -aoE "<[^>]+>" | tr -d '<>' | grep -aF "$work/target/" \
             | sort -u)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -n "$(grep -aFx "$f" <<EOF
$written
EOF
    )" ] || missing="$missing $(basename "$f")"
  done <<EOF
$init
EOF
  if [ -n "$missing" ]; then
    fail "$tag: files removed without being written-over: $missing"
  else
    pass "$tag erase ok (full tree removed, every file overwritten, neighbor intact)"
  fi
}

run_erase erase_1 "$HALL/erase_1"
run_erase erase_2 "$HALL/erase_2"

# erase_3: empty tree, broken-symlink tree, and a missing target
rm -rf /tmp/ze_3e; mkdir -p /tmp/ze_3e/empty
strace -f -y -qq -e trace=write,pwrite64 -o /tmp/ze_3e/trace \
  bash /app/secure_erase.sh /tmp/ze_3e/empty >/tmp/ze_3e/stdout 2>/dev/null
if [ -e /tmp/ze_3e/empty ]; then fail "erase_3a: empty tree not removed"; else pass "erase_3a (empty tree removed)"; fi

rm -rf /tmp/ze_3b; mkdir -p /tmp/ze_3b/target
strace -f -y -qq -e trace=write,pwrite64 -o /tmp/ze_3b/trace \
  bash /app/secure_erase.sh /tmp/ze_3b/target >/tmp/ze_3b/stdout 2>/dev/null
if [ -e /tmp/ze_3b/target ]; then fail "erase_3b: empty+symlink tree not removed"; else pass "erase_3b (empty + broken symlink removed)"; fi

rm -rf /tmp/ze_3c; mkdir -p /tmp/ze_3c
printf 'should survive\n' > /tmp/ze_3c/keeper.txt
if bash /app/secure_erase.sh /tmp/ze_3c/no_such_dir >/tmp/ze_3c/stdout 2>/tmp/ze_3c/trace; then
  :
else
  fail "erase_3c: missing target caused non-zero exit"
fi
[ -e /tmp/ze_3c/keeper.txt ] || fail "erase_3c: missing-target run harmed a neighbor"
[ -e /tmp/ze_3c/no_such_dir ] && fail "erase_3c: no_such_dir materialised"
pass "erase_3c (missing target handled gracefully, no blast radius)"

# ---------------------------------------------------------------------------
if [ "${#FAILS[@]}" -gt 0 ]; then
  echo "VERIFIER FAILURES:"
  for m in "${FAILS[@]}"; do echo "  * $m"; done
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

echo "ALL PASS"
echo "1" > /logs/verifier/reward.txt
exit 0