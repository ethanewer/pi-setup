#!/usr/bin/env bash
# Hidden case 2: reuse a PKCS#7 object after a parse FAILURE -- a rejected
# message (multiple certificates, MBEDTLS_ERR_PKCS7_FEATURE_UNAVAILABLE)
# between two valid three-signer parses. The cleanup that runs internally
# after the failed parse must not double-free stale signer records.
set -u
cd "$(dirname "$0")" || exit 9
gcc -std=c99 -DMBEDTLS_ALLOW_PRIVATE_ACCESS \
    -I /app/src/include -I /app/src/tf-psa-crypto/include \
    -I /app/src/tf-psa-crypto/drivers/builtin/include \
    -I /app/src/build/tf-psa-crypto/include \
    -o hc2 ./hc2.c \
    /app/src/build/library/libmbedtls.a \
    /app/src/build/library/libmbedx509.a \
    /app/src/build/tf-psa-crypto/core/libtfpsacrypto.a \
    2> compile.log || { cat compile.log >&2; exit 9; }
./hc2 /app/src/framework/data_files/pkcs7_data_3_signed.der \
      /app/src/framework/data_files/pkcs7_data_multiple_certs_signed.der
exit $?