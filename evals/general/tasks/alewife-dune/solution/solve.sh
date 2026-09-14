#!/bin/bash
# Oracle for alewife-dune: applies the bounded-copy fix to the real
# Mbed-TLS/mbedtls tree at /app/src (the two missing size checks in the
# ECDSA raw<->DER signature conversion code), writes the failing
# reproduction into the project's own test data, proves everything with the
# project's own generated test harness, and writes /app/summary.md.
# Reads only /app and /solution, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied bounded-copy fix"

# Rebuild the library with the fix (incremental: one object file).
if ! make -j1 lib > /tmp/oracle_lib.log 2>&1; then
    echo "oracle: make lib failed; tail:" >&2
    tail -30 /tmp/oracle_lib.log >&2
    exit 1
fi

# Deliverable reproduction: extend the project's own test data with the two
# oversized-coordinate cases (one per conversion direction), as the
# instruction demands an agent to do, then show them PASS on the fixed tree.
printf '\n' >> tests/suites/test_suite_psa_crypto_util.data
cat /solution/repro.data >> tests/suites/test_suite_psa_crypto_util.data
rm -f tests/test_suite_psa_crypto_util tests/test_suite_psa_crypto_util.c tests/test_suite_psa_crypto_util.datax
if ! make -C tests test_suite_psa_crypto_util > /tmp/oracle_suite.log 2>&1; then
    echo "oracle: suite build failed; tail:" >&2
    tail -30 /tmp/oracle_suite.log >&2
    exit 1
fi
if ! tests/test_suite_psa_crypto_util > /tmp/oracle_repro.log 2>&1; then
    echo "oracle: reproduction cases did not pass; tail:" >&2
    tail -30 /tmp/oracle_repro.log >&2
    exit 1
fi
grep -q "PASSED (43 / 43 tests" /tmp/oracle_repro.log || {
    echo "oracle: reproduction run did not report 43/43 PASSED" >&2
    tail -10 /tmp/oracle_repro.log >&2
    exit 1
}
grep -F "very large input (544-bit)" /tmp/oracle_repro.log | grep -q PASS || {
    echo "oracle: 544-bit reproduction cases did not print PASS" >&2
    tail -10 /tmp/oracle_repro.log >&2
    exit 1
}
echo "oracle: reproduction green on the fixed tree (43/43)"
# The two reproduction cases above (raw->DER and DER->raw at 544-bit,
# from /solution/repro.data) are byte-identical to the upstream golden
# regression cases the fix commit added, so the 43/43 run just above IS
# the upstream 43-case golden suite. The verifier additionally rebuilds
# and runs the golden suite itself from its own /tests mount.

# Regression: the project's own existing PSA crypto and PK suites must stay
# green on the repaired tree.
if ! make -C tests test_suite_psa_crypto test_suite_pk > /tmp/oracle_exist_build.log 2>&1; then
    echo "oracle: existing suite build failed; tail:" >&2
    tail -20 /tmp/oracle_exist_build.log >&2
    exit 1
fi
tests/test_suite_psa_crypto > /tmp/oracle_psa.log 2>&1 || {
    echo "oracle: test_suite_psa_crypto failed" >&2
    tail -20 /tmp/oracle_psa.log >&2
    exit 1
}
tests/test_suite_pk > /tmp/oracle_pk.log 2>&1 || {
    echo "oracle: test_suite_pk failed" >&2
    tail -20 /tmp/oracle_pk.log >&2
    exit 1
}
grep -q "1945 / 1945" /tmp/oracle_psa.log && grep -q "407 / 407" /tmp/oracle_pk.log || {
    echo "oracle: expected PASSED counts not found" >&2
    exit 1
}
echo "oracle: existing suites green (psa_crypto 1945/1945, pk 407/407)"

# Deliverable summary.
cat > /app/summary.md <<'MD'
# Change summary (oracle)

## Symptom
Converting an ECDSA signature between the raw r||s form and ASN.1 DER form
crashes the process (glibc FORTIFY abort, `*** buffer overflow detected ***`
then SIGABRT / exit 134) when the caller supplies a coordinate size larger
than the largest curve the build supports (521-bit => 66-byte coordinates).
A 544-bit value (68-byte coordinates) triggers it in both directions
(raw -> DER and DER -> raw).

## Root cause
Both conversion routines derive the coordinate byte length straight from the
caller-supplied bit size (`coordinate_len = PSA_BITS_TO_BYTES(bits)`) and
copy r and s into fixed-size stack buffers sized for the largest *supported*
curve (`PSA_BITS_TO_BYTES(PSA_VENDOR_ECC_MAX_CURVE_BITS)` = 66 bytes; the
DER->raw direction uses the matching 132-byte raw output staging buffer).
There is no check that the incoming coordinate length fits those buffers, so
a 544-bit input makes `memcpy`/`memset` write 68 (resp. 136) bytes into a
66-byte (resp. 132-byte) buffer: deterministic FORTIFY abort on hardened
builds, silent stack corruption otherwise.

## Fix
Add an explicit bounds check before any copying, in both directions, that
returns the library's documented `MBEDTLS_ERR_ASN1_BUF_TOO_SMALL` when the
derived coordinate length exceeds the fixed internal buffers. The checks are:
`coordinate_len > sizeof(r)` in the raw->DER path and
`2 * coordinate_size > sizeof(raw_tmp)` in the DER->raw path. Legal inputs
(<= 521 bits, including the 528-bit boundary whose 66-byte coordinates still
fit) are untouched, byte-for-byte.

## Verification
- Reproduction: two new cases in tests/suites/test_suite_psa_crypto_util.data
  (raw->DER and DER->raw at 544-bit, each expecting
  MBEDTLS_ERR_ASN1_BUF_TOO_SMALL) fail with the buffer-overflow abort on the
  unpatched tree and print PASS on the patched tree.
- `make -C tests test_suite_psa_crypto_util && tests/test_suite_psa_crypto_util`
  -> `PASSED (43 / 43 tests (0 skipped))`.
- Existing suites remain green: test_suite_psa_crypto `PASSED (1945 / 1945)`,
  test_suite_pk `PASSED (407 / 407)`.
MD

echo "oracle: fix applied, reproduction (== upstream golden) + existing suites green, summary written"
exit 0