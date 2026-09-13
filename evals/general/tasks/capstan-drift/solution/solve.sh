#!/bin/bash
# Oracle for capstan-drift: applies the one-line source fix to the real
# Mbed-TLS tree at /app/src (mbedtls_pkcs7_free() must reset the whole
# structure so a reused object cannot carry stale signer records), writes
# /app/summary.md, then proves the work with the project's own machinery.
# Reads only /app, /solution and /app/src.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch || { echo "oracle: git apply failed" >&2; exit 1; }
echo "oracle: applied pkcs7 cleanup fix"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: an application that reused one mbedtls_pkcs7 object across parse/cleanup
cycles crashed the whole process with "free(): double free detected in tcache
2". mbedtls_pkcs7_free() released the raw DER buffer, the certificate list,
the CRL and the linked signer records but then only reset `raw.p` to NULL.
After the free, the embedded signer record and the signer linked-list pointer
still referenced freed heap blocks. Parsing a follow-up message with a
zero-length signerInfos SET does not touch those fields, so the next
mbedtls_pkcs7_free() walked the stale list and handed the same node to the
allocator twice, aborting with exit 134.

Fix: in mbedtls_pkcs7_free(), replace `pkcs7->raw.p = NULL` with
`mbedtls_platform_zeroize(pkcs7, sizeof(*pkcs7))`, i.e. reset the entire
structure instead of one field. The object is then a clean slate for the
next parse, and any subsequent cleanup is a no-op without touching freed
memory. No other behaviour changes: parsing fresh objects, all signer-count
shapes and rejected (malformed) messages behave exactly as before.

Verification: rebuilt with the project's own tooling
(`cmake --build build --target test_suite_pkcs7 -j1`) and ran the project's
own test binaries built at image time (from the repository root, where the
suite fixture paths resolve):
- pkcs7 suite      -> PASSED (all cases pass, a handful skipped)
- x509parse suite  -> PASSED (all cases pass)
The /app/repro.c reuse scenario now prints REUSE-OK and exits 0.
MD

# Prove the tree compiles and the project's own tests stay green, offline.
if ! cmake --build build --target test_suite_pkcs7 -j1 > /tmp/oracle_build.log 2>&1; then
    echo "oracle: rebuild failed; tail:" >&2
    tail -30 /tmp/oracle_build.log >&2
    exit 1
fi
if ! ( cd build && exec tests/test_suite_pkcs7 ) > /tmp/oracle_suite.log 2>&1; then
    echo "oracle: pkcs7 suite failed; tail:" >&2
    tail -20 /tmp/oracle_suite.log >&2
    exit 1
fi
grep -qE "PASSED \(8[0-9]{2} / 8[0-9]{2} tests" /tmp/oracle_suite.log || {
    echo "oracle: pkcs7 suite did not print the expected PASSED line" >&2
    tail -5 /tmp/oracle_suite.log >&2
    exit 1
}
if ! ( cd build && exec tests/test_suite_x509parse ) > /tmp/oracle_x509.log 2>&1; then
    echo "oracle: x509parse suite failed; tail:" >&2
    tail -10 /tmp/oracle_x509.log >&2
    exit 1
fi
grep -qE "PASSED \(8[0-9]{2} / 8[0-9]{2} tests" /tmp/oracle_x509.log || {
    echo "oracle: x509parse suite did not print the expected PASSED line" >&2
    tail -5 /tmp/oracle_x509.log >&2
    exit 1
}

# Direct reproduction through the authored reproducer: must return REUSE-OK.
gcc -std=c99 -DMBEDTLS_ALLOW_PRIVATE_ACCESS \
    -I include -I tf-psa-crypto/include -I tf-psa-crypto/drivers/builtin/include \
    -I build/tf-psa-crypto/include \
    -o /tmp/oracle_repro /app/repro.c \
    build/library/libmbedtls.a build/library/libmbedx509.a \
    build/tf-psa-crypto/core/libtfpsacrypto.a || {
    echo "oracle: repro compile failed" >&2; exit 1; }
OUT=$(/tmp/oracle_repro framework/data_files/pkcs7_data_multiple_signed.der \
                          framework/data_files/pkcs7_data_no_signers.der)
RC=$?
[ "$RC" -eq 0 ] && [ "$OUT" = "REUSE-OK" ] || {
    echo "oracle: repro failed rc=$RC out='$OUT'" >&2; exit 1; }
echo "oracle: repro OK (exit 0, stdout 'REUSE-OK')"

echo "oracle: fix applied, summary written, project suites green, repro OK"
exit 0