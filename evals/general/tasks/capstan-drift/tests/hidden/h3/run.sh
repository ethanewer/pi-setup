#!/usr/bin/env bash
# Hidden case 3: deep reuse of one object across four cycles with signer
# counts 3, 1, 3, 0, asserting the parsed signer count after every cycle and
# that a single-signer parse leaves no linked signer records behind.
set -u
cd "$(dirname "$0")" || exit 9
gcc -std=c99 -DMBEDTLS_ALLOW_PRIVATE_ACCESS \
    -I /app/src/include -I /app/src/tf-psa-crypto/include \
    -I /app/src/tf-psa-crypto/drivers/builtin/include \
    -I /app/src/build/tf-psa-crypto/include \
    -o hc3 ./hc3.c \
    /app/src/build/library/libmbedtls.a \
    /app/src/build/library/libmbedx509.a \
    /app/src/build/tf-psa-crypto/core/libtfpsacrypto.a \
    2> compile.log || { cat compile.log >&2; exit 9; }
./hc3 /app/src/framework/data_files/pkcs7_data_3_signed.der \
      /app/src/framework/data_files/pkcs7_data_without_cert_signed.der
exit $?