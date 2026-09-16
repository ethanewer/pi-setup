#!/bin/bash
# Verifier for ballast-berm: an upstream-clone debugging task on mbedtls.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# psa_cipher_decrypt() rejects CCM*-no-tag messages whose nonce-plus-
# ciphertext input is shorter than one AES block, even though valid CCM*
# messages only need to be as long as the nonce. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, the regression-test data the
#      image overlays into tests/suites/ is byte-identical to the upstream
#      regression test, library/psa_crypto.c holds a non-empty diff, and
#      nothing else in the repository changed);
#   1. rebuilds the library and the psa_crypto test suite from the repaired
#      tree (incremental, ~seconds at 1 CPU) and requires the project's own
#      suite to pass end to end: PASSED (1949 / 1949 tests (309 skipped)),
#      naming the two upstream regression cases explicitly;
#   2. compiles and runs two authored hidden-case drivers against the
#      rebuilt library: short-message CCM* decryption with AES-128 keys and
#      ciphertext lengths (1, 4, 5, 8, 15, 16 bytes) the regression tests
#      do not use, and AES-256 keys with lengths (0, 1, 4, 16, 40 bytes).
#      Every vector must decrypt to the exact plaintext.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=dd48f0f23f8b5189031d6f3ac519b2b6113bd9e7
FIX_SHA=7b6ddfcd25d95a1c6a452158db9205a6372b4426
GOLDEN=/opt/golden/test_suite_psa_crypto.data
GOLDEN_SHA=a22413025ce88aa659c901235b3fe6a8d67193601c927dcca211795545a4e72a
DATA=suites/test_suite_psa_crypto.data

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  fail "/app/src is not a git clone"
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  fail "/app/src HEAD is not the pinned parent commit"
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
  echo "ok: the upstream fix commit is not present in the clone"
fi

if [ -z "$(git -C "$SRC" diff -- library/psa_crypto.c 2>/dev/null || true)" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  echo "ok: library/psa_crypto.c differs from the pinned commit"
fi

tree_golden=$(sha256sum < "$SRC/tests/$DATA" 2>/dev/null | cut -d' ' -f1)
if [ "$tree_golden" = "$GOLDEN_SHA" ]; then
  echo "ok: tests/suites/test_suite_psa_crypto.data is byte-identical to the upstream regression test"
else
  fail "tests/suites/test_suite_psa_crypto.data was altered (${tree_golden:-missing})"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
expected=" M library/psa_crypto.c"$'\n'" M tests/$DATA"
if [ "$porcelain" = "$expected" ]; then
  echo "ok: working tree differs from the pinned commit only in the fix and the overlaid regression data"
else
  fail "unexpected working-tree changes:"
  printf '%s\n' "$porcelain" | head -10 | sed 's/^/    /' >&2
fi

# ---------- 1. rebuild and run the project's own suite -----------------------
echo "== rebuild library + psa_crypto suite from the repaired tree =="
# Force a genuine build from the agent's sources and the sha-checked data:
# touching psa_crypto.c makes make recompile the source the tree actually
# carries (mtime spoofing or patching a stale object/archive cannot survive),
# and cleaning tests/ discards any hand-placed suite binary or generated
# test driver so the honest, freshly generated suite is what runs.
touch "$SRC/library/psa_crypto.c"
( cd "$SRC" && make -C tests clean > /tmp/tests-clean.log 2>&1 ) || true
if ( cd "$SRC" && make -j1 lib > /tmp/rebuild-lib.log 2>&1 \
      && make -C tests -j1 test_suite_psa_crypto > /tmp/rebuild-tests.log 2>&1 ); then
  echo "ok: incremental rebuild succeeded"
else
  fail "incremental rebuild failed"
  tail -30 /tmp/rebuild-lib.log /tmp/rebuild-tests.log | sed 's/^/    /' >&2 || true
fi

echo "== the project's own psa_crypto suite =="
if [ "$reward" = 1 ]; then
  if ( cd "$SRC" && ./tests/test_suite_psa_crypto > /tmp/suite.out 2>&1 ); then
    :
  fi
  if grep -qF "PASSED (1949 / 1949 tests (309 skipped))" /tmp/suite.out 2>/dev/null; then
    echo "ok: full suite green: PASSED (1949 / 1949 tests (309 skipped))"
  else
    fail "the project's own suite is not fully green"
    tail -12 /tmp/suite.out 2>/dev/null | sed 's/^/    /' >&2 || true
  fi
fi

echo "== upstream regression cases present in the run =="
for name in "PSA symmetric decrypt: CCM*-no-tag, NIST DVPT AES-128 #15, 0 bytes" \
            "PSA symmetric decrypt: CCM*-no-tag, NIST DVPT AES-128 #15, 2 bytes"; do
  if grep -F "$name" /tmp/suite.out 2>/dev/null | grep -Fqv "FAILED"; then
    echo "ok: golden case passes: $name"
  else
    fail "golden case did not pass: $name"
  fi
done

# ---------- 2. authored hidden cases -----------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  cname=$(basename "$case")
  for f in "$case"*.c; do
    [ -f "$f" ] || continue
    bin="/tmp/hidden_${cname}"
    if ! cc -I"$SRC/include" -I"$SRC/tf-psa-crypto/include" \
         -o "$bin" "$f" \
         "$SRC/library/libmbedcrypto.a" \
         "$SRC/library/libmbedtls.a" \
         "$SRC/library/libmbedx509.a" > "/tmp/cc-$cname.log" 2>&1; then
      fail "hidden case $cname did not compile"
      tail -15 "/tmp/cc-$cname.log" | sed 's/^/    /' >&2
      continue
    fi
    out=$("$bin" 2>&1)
    rc=$?
    if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q "0 failed"; then
      echo "ok: hidden case $cname: $(echo "$out" | tail -1)"
    else
      fail "hidden case $cname"
      printf '%s\n' "$out" | tail -8 | sed 's/^/    /' >&2
    fi
  done
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0