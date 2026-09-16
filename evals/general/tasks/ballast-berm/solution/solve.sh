#!/bin/bash
# Oracle for ballast-berm: applies the minimal upstream fix to the mbedtls
# checkout at /app/src (remove the CCM*-specific one-AES-block minimum from
# psa_cipher_decrypt so only the IV-length minimum remains), then rebuilds
# and runs the project's own regression suite against the repaired tree.
set -e

python3 /solution/fix_psa_crypto.py /app/src/library/psa_crypto.c

echo "== rebuilt library + suite, running the full psa_crypto suite =="
cd /app/src && make -j1 lib && make -C tests -j1 test_suite_psa_crypto
cd /app/src
cd tests
./test_suite_psa_crypto