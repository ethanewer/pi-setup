#!/usr/bin/env bash
# Hidden case 1: object reuse across four parse/free cycles with different
# message shapes (3 signers, authored zero-signer message, 3 signers, authored
# zero-signer message), asserting parsed signer counts and that no stale
# signer state survives a zero-signer parse.
set -u
cd "$(dirname "$0")" || exit 9
gcc -std=c99 -DMBEDTLS_ALLOW_PRIVATE_ACCESS \
    -I /app/src/include -I /app/src/tf-psa-crypto/include \
    -I /app/src/tf-psa-crypto/drivers/builtin/include \
    -I /app/src/build/tf-psa-crypto/include \
    -o hc1 ./hc1.c \
    /app/src/build/library/libmbedtls.a \
    /app/src/build/library/libmbedx509.a \
    /app/src/build/tf-psa-crypto/core/libtfpsacrypto.a \
    2> compile.log || { cat compile.log >&2; exit 9; }
./hc1 /app/src/framework/data_files/pkcs7_data_3_signed.der
exit $?