/*
 * Hidden case H2: reuse a PKCS#7 object after a parse FAILURE.
 *
 * The object is first populated with a valid three-signer message, then
 * freed. The follow-up parse is of a message mbedtls rejects with
 * MBEDTLS_ERR_PKCS7_FEATURE_UNAVAILABLE; on parse failure the parser calls
 * mbedtls_pkcs7_free() internally, which on the buggy tree walks the
 * signer records left dangling by the first free and aborts with a
 * double free. The correct behaviour is a clean negative return and a
 * still-usable object that can parse a third message.
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
    unsigned char *ok_buf = NULL, *err_buf = NULL;
    size_t ok_len = 0, err_len = 0;
    mbedtls_pkcs7 pkcs7;
    int res;

    if (argc != 3) { fprintf(stderr, "usage: hc2 <three-signer.der> <rejected.der>\n"); return 2; }
    if (load_file(argv[1], &ok_buf, &ok_len) != 0) { fprintf(stderr, "cannot read %s\n", argv[1]); return 2; }
    if (load_file(argv[2], &err_buf, &err_len) != 0) { fprintf(stderr, "cannot read %s\n", argv[2]); return 2; }
    if (psa_crypto_init() != PSA_SUCCESS) { fprintf(stderr, "psa_crypto_init failed\n"); return 2; }

    mbedtls_pkcs7_init(&pkcs7);

    res = mbedtls_pkcs7_parse_der(&pkcs7, ok_buf, ok_len);
    if (res != MBEDTLS_PKCS7_SIGNED_DATA) { fprintf(stderr, "first parse: %d\n", res); goto fail; }
    if (pkcs7.signed_data.no_of_signers != 3) {
        fprintf(stderr, "first parse signer count %d, expected 3\n",
                pkcs7.signed_data.no_of_signers); goto fail;
    }
    mbedtls_pkcs7_free(&pkcs7);

    /* second parse must fail cleanly. On the buggy tree the internal
     * cleanup after the failure uses the freed signer records from the
     * first parse and the process aborts here. */
    res = mbedtls_pkcs7_parse_der(&pkcs7, err_buf, err_len);
    if (res >= 0) {
        fprintf(stderr, "second parse unexpectedly succeeded: %d\n", res); goto fail;
    }

    /* object must still parse a valid message afterwards */
    res = mbedtls_pkcs7_parse_der(&pkcs7, ok_buf, ok_len);
    if (res != MBEDTLS_PKCS7_SIGNED_DATA) { fprintf(stderr, "third parse: %d\n", res); goto fail; }
    if (pkcs7.signed_data.no_of_signers != 3) {
        fprintf(stderr, "third parse signer count %d, expected 3\n",
                pkcs7.signed_data.no_of_signers); goto fail;
    }
    mbedtls_pkcs7_free(&pkcs7);

    free(ok_buf); free(err_buf);
    printf("HIDDEN2-OK\n");
    return 0;

fail:
    free(ok_buf); free(err_buf);
    fprintf(stderr, "HIDDEN2-FAIL\n");
    return 1;
}