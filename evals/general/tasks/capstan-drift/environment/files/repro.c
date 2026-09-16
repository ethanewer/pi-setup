/*
 * capstan-drift reproducer (authored for this task, not part of upstream).
 *
 * Demonstrates the PKCS#7 object-reuse double free: parse a signed-data
 * message with several signers, run cleanup on the object, then parse a
 * follow-up message with NO signers into the same object and run cleanup
 * again. On the buggy tree this aborts with
 *
 *     free(): double free detected in tcache 2
 *     Aborted (core dumped)
 *
 * and exit 134. On a fixed tree it must print REUSE-OK and exit 0.
 *
 * Usage: repro <multiple-signer.der> <zero-signer.der>
 */
#include <stdio.h>
#include <stdlib.h>
#include "mbedtls/pkcs7.h"
#include "mbedtls/x509_crt.h"
#include "psa/crypto.h"

static int load_file(const char *path, unsigned char **buf, size_t *len)
{
    FILE *f = fopen(path, "rb");
    long n;
    if (f == NULL)
        return -1;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return -1; }
    n = ftell(f);
    if (n < 0) { fclose(f); return -1; }
    if (fseek(f, 0, SEEK_SET) != 0) { fclose(f); return -1; }
    *buf = (unsigned char *) calloc(1, (size_t) n);
    if (*buf == NULL) { fclose(f); return -1; }
    if (fread(*buf, 1, (size_t) n, f) != (size_t) n) { fclose(f); return -1; }
    fclose(f);
    *len = (size_t) n;
    return 0;
}

int main(int argc, char **argv)
{
    unsigned char *first = NULL, *second = NULL;
    size_t first_len = 0, second_len = 0;
    mbedtls_pkcs7 pkcs7;
    int res;

    if (argc != 3) {
        fprintf(stderr, "usage: repro <with-signers.der> <no-signers.der>\n");
        return 2;
    }
    if (load_file(argv[1], &first, &first_len) != 0) {
        fprintf(stderr, "cannot read %s\n", argv[1]); return 2;
    }
    if (load_file(argv[2], &second, &second_len) != 0) {
        fprintf(stderr, "cannot read %s\n", argv[2]); return 2;
    }
    if (psa_crypto_init() != PSA_SUCCESS) {
        fprintf(stderr, "psa_crypto_init failed\n"); return 2;
    }

    mbedtls_pkcs7_init(&pkcs7);

    res = mbedtls_pkcs7_parse_der(&pkcs7, first, first_len);
    if (res != MBEDTLS_PKCS7_SIGNED_DATA) {
        fprintf(stderr, "first parse returned %d (expected %d)\n",
                res, MBEDTLS_PKCS7_SIGNED_DATA);
        return 1;
    }
    mbedtls_pkcs7_free(&pkcs7);

    /* The reuse: parse a different message into the same object. On the
     * buggy tree the cleanup above left stale signer records in the
     * object, and the cleanup below frees them a second time -> abort. */
    res = mbedtls_pkcs7_parse_der(&pkcs7, second, second_len);
    if (res != MBEDTLS_PKCS7_SIGNED_DATA) {
        fprintf(stderr, "second parse returned %d (expected %d)\n",
                res, MBEDTLS_PKCS7_SIGNED_DATA);
        return 1;
    }
    mbedtls_pkcs7_free(&pkcs7);

    free(first);
    free(second);
    printf("REUSE-OK\n");
    return 0;
}