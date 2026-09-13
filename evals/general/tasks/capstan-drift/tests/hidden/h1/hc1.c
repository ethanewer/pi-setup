/*
 * Hidden case H1: PKCS#7 object reuse across four parse/free cycles with
 * differing message shapes (3 signers, zero signers, 3 signers, zero signers).
 *
 * The bug being exercised: mbedtls_pkcs7_free() releases the signer records
 * and the raw DER buffer but resets only raw.p, leaving the signer linked
 * list and the embedded signer record dangling. Parsing a message with zero
 * signers never touches those fields, so the next free() walks freed memory
 * and the process aborts with a glibc double-free error.
 *
 * The upstream regression test for this bug pairs one specific
 * multiple-signer file with one specific zero-signer file for two cycles.
 * This case uses a different signer count (3), a different zero-signer
 * message (authored here, not taken from the upstream data files), four
 * cycles, and asserts the parsed signer count after every cycle plus the
 * absence of stale signer state after each zero-signer parse.
 */
#include <stdio.h>
#include <stdlib.h>
#include "mbedtls/pkcs7.h"
#include "mbedtls/x509_crt.h"
#include "psa/crypto.h"

/*
 * Authored zero-signer PKCS#7 SignedData message (no certificates, empty
 * signerInfos SET), hand-built DER:
 *   ContentInfo ::= SEQUENCE {
 *       contentType OID 1.2.840.113549.1.7.2 (signedData),
 *       content     [0] EXPLICIT SignedData ::= SEQUENCE {
 *           version           INTEGER 1,
 *           digestAlgorithms  SET { SEQUENCE { OID 2.16.840.1.101.3.4.2.1 } },
 *           encapContentInfo  SEQUENCE { contentType OID 1.2.840.113549.1.7.1 },
 *           signerInfos       SET (empty) } }
 */
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
    unsigned char *three_buf = NULL;
    size_t three_len = 0;
    mbedtls_pkcs7 pkcs7;
    int res;

    if (argc != 2) { fprintf(stderr, "usage: hc1 <three-signer.der>\n"); return 2; }
    if (load_file(argv[1], &three_buf, &three_len) != 0) {
        fprintf(stderr, "cannot read %s\n", argv[1]); return 2;
    }
    if (psa_crypto_init() != PSA_SUCCESS) { fprintf(stderr, "psa_crypto_init failed\n"); return 2; }

    mbedtls_pkcs7_init(&pkcs7);

    /* cycle 1: three-signer message */
    res = mbedtls_pkcs7_parse_der(&pkcs7, three_buf, three_len);
    if (res != MBEDTLS_PKCS7_SIGNED_DATA) { fprintf(stderr, "cycle1 parse: %d\n", res); goto fail; }
    if (pkcs7.signed_data.no_of_signers != 3) {
        fprintf(stderr, "cycle1 signer count %d, expected 3\n", pkcs7.signed_data.no_of_signers); goto fail;
    }
    if (pkcs7.signed_data.signers.next == NULL) {
        fprintf(stderr, "cycle1: expected linked signer records\n"); goto fail;
    }
    mbedtls_pkcs7_free(&pkcs7);

    /* cycle 2: zero-signer message; on the buggy tree the stale signer
     * list makes this free() abort with a double free. */
    res = mbedtls_pkcs7_parse_der(&pkcs7, zero_signer_der, sizeof(zero_signer_der));
    if (res != MBEDTLS_PKCS7_SIGNED_DATA) { fprintf(stderr, "cycle2 parse: %d\n", res); goto fail; }
    if (pkcs7.signed_data.no_of_signers != 0) {
        fprintf(stderr, "cycle2 signer count %d, expected 0\n", pkcs7.signed_data.no_of_signers); goto fail;
    }
    /* a zero-signer message must leave no signer state behind */
    if (pkcs7.signed_data.signers.serial.p != NULL ||
        pkcs7.signed_data.signers.next != NULL) {
        fprintf(stderr, "cycle2: stale signer state after zero-signer parse\n"); goto fail;
    }
    mbedtls_pkcs7_free(&pkcs7);

    /* cycle 3: three-signer message again */
    res = mbedtls_pkcs7_parse_der(&pkcs7, three_buf, three_len);
    if (res != MBEDTLS_PKCS7_SIGNED_DATA) { fprintf(stderr, "cycle3 parse: %d\n", res); goto fail; }
    if (pkcs7.signed_data.no_of_signers != 3) {
        fprintf(stderr, "cycle3 signer count %d, expected 3\n", pkcs7.signed_data.no_of_signers); goto fail;
    }
    mbedtls_pkcs7_free(&pkcs7);

    /* cycle 4: zero-signer message again */
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

    free(three_buf);
    printf("HIDDEN1-OK\n");
    return 0;

fail:
    free(three_buf);
    fprintf(stderr, "HIDDEN1-FAIL\n");
    return 1;
}