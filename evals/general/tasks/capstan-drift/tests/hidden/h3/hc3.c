/*
 * Hidden case H3: deep reuse of one PKCS#7 object across four parse/free
 * cycles with different signer counts (3, 1, 3, 0), asserting the parsed
 * signer count after every cycle and that no signer record leaks from one
 * message into the next.
 *
 * The buggy cleanup leaves the signer linked list dangling after each free.
 * Parsing a single-signer message overwrites the embedded signer record but
 * not the list pointer, so the following free() still walks freed nodes and
 * aborts with a double free. Only a cleanup that resets the whole structure
 * survives the full sequence.
 */
#include <stdio.h>
#include <stdlib.h>
#include "mbedtls/pkcs7.h"
#include "mbedtls/x509_crt.h"
#include "psa/crypto.h"

/* Same authored zero-signer SignedData message as hidden case hc1. */
static const unsigned char zero_signer_der[] = {
    0x30, 0x30, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02,
    0xA0, 0x23, 0x30, 0x21, 0x02, 0x01, 0x01, 0x31, 0x0D, 0x30, 0x0B, 0x06, 0x09,
    0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x30, 0x0B, 0x06, 0x09,
    0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x01, 0x31, 0x00
};

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
    unsigned char *b3 = NULL, *b1 = NULL;
    size_t l3 = 0, l1 = 0;
    mbedtls_pkcs7 pkcs7;
    int res;

    if (argc != 3) { fprintf(stderr, "usage: hc3 <three-signer.der> <one-signer.der>\n"); return 2; }
    if (load_file(argv[1], &b3, &l3) != 0) { fprintf(stderr, "cannot read %s\n", argv[1]); return 2; }
    if (load_file(argv[2], &b1, &l1) != 0) { fprintf(stderr, "cannot read %s\n", argv[2]); return 2; }
    if (psa_crypto_init() != PSA_SUCCESS) { fprintf(stderr, "psa_crypto_init failed\n"); return 2; }

    mbedtls_pkcs7_init(&pkcs7);

    /* cycle 1: three signers */
    res = mbedtls_pkcs7_parse_der(&pkcs7, b3, l3);
    if (res != MBEDTLS_PKCS7_SIGNED_DATA) { fprintf(stderr, "cycle1 parse: %d\n", res); goto fail; }
    if (pkcs7.signed_data.no_of_signers != 3) {
        fprintf(stderr, "cycle1 signer count %d, expected 3\n", pkcs7.signed_data.no_of_signers); goto fail;
    }
    mbedtls_pkcs7_free(&pkcs7);

    /* cycle 2: one signer. The embedded record is overwritten but on the
     * buggy tree the list pointer still references the freed cycle-1 nodes,
     * which the following free() then touches. */
    res = mbedtls_pkcs7_parse_der(&pkcs7, b1, l1);
    if (res != MBEDTLS_PKCS7_SIGNED_DATA) { fprintf(stderr, "cycle2 parse: %d\n", res); goto fail; }
    if (pkcs7.signed_data.no_of_signers != 1) {
        fprintf(stderr, "cycle2 signer count %d, expected 1\n", pkcs7.signed_data.no_of_signers); goto fail;
    }
    if (pkcs7.signed_data.signers.serial.p == NULL ||
        pkcs7.signed_data.signers.next != NULL) {
        fprintf(stderr, "cycle2: signer record inconsistent after single-signer parse\n"); goto fail;
    }
    mbedtls_pkcs7_free(&pkcs7);

    /* cycle 3: three signers again */
    res = mbedtls_pkcs7_parse_der(&pkcs7, b3, l3);
    if (res != MBEDTLS_PKCS7_SIGNED_DATA) { fprintf(stderr, "cycle3 parse: %d\n", res); goto fail; }
    if (pkcs7.signed_data.no_of_signers != 3) {
        fprintf(stderr, "cycle3 signer count %d, expected 3\n", pkcs7.signed_data.no_of_signers); goto fail;
    }
    mbedtls_pkcs7_free(&pkcs7);

    /* cycle 4: zero signers */
    res = mbedtls_pkcs7_parse_der(&pkcs7, zero_signer_der, sizeof(zero_signer_der));
    if (res != MBEDTLS_PKCS7_SIGNED_DATA) { fprintf(stderr, "cycle4 parse: %d\n", res); goto fail; }
    if (pkcs7.signed_data.no_of_signers != 0) {
        fprintf(stderr, "cycle4 signer count %d, expected 0\n", pkcs7.signed_data.no_of_signers); goto fail;
    }
    if (pkcs7.signed_data.signers.serial.p != NULL ||
        pkcs7.signed_data.signers.next != NULL) {
        fprintf(stderr, "cycle4: stale signer state after zero-signer parse\n"); goto fail;
    }
    mbedtls_pkcs7_free(&pkcs7);

    free(b3); free(b1);
    printf("HIDDEN3-OK\n");
    return 0;

fail:
    free(b3); free(b1);
    fprintf(stderr, "HIDDEN3-FAIL\n");
    return 1;
}