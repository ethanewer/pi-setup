/* check.c - the hollow-ledge vault validation routine.
 * Reverse it to recover the VALID secret the system accepts.
 *
 * A valid secret is a printable ASCII string of exactly 12 bytes, S[0..11],
 * such that running every byte through the byte-bijection
 *     f(x) = ( (x * 0x35 + 0x2f) ^ 0xa5 ) & 0xff
 * reproduces the stored fingerprint FP below. f is a permutation of the 256
 * byte values (multiplication by 0x35 is invertible mod 256). To recover the
 * secret, invert f:  x = ( ((y ^ 0xa5) - 0x2f) * inv35 ) & 0xff  where inv35
 * is the mod-256 inverse of 0x35 (inv35 = 109), and apply it to each FP byte.
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>

static const uint8_t FP[12] = { 0x65, 0xbd, 0x6c, 0x6c, 0x8f, 0x77, 0x25, 0x50, 0x8f, 0x6c, 0x96, 0x12 };

static uint8_t f(uint8_t x) {
    return (uint8_t)(((x * 0x35u) + 0x2fu) ^ 0xa5u);
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: check <secret>\n"); return 2; }
    size_t n = strlen(argv[1]);
    if (n != 12) { fputs("REJECT\n", stdout); return 1; }
    for (size_t i = 0; i < 12; i++) {
        unsigned char b = (unsigned char)argv[1][i];
        if (b < 0x20 || b > 0x7e) { fputs("REJECT\n", stdout); return 1; }
        if (f(b) != FP[i]) { fputs("REJECT\n", stdout); return 1; }
    }
    fputs("ACCEPT\n", stdout);
    return 0;
}
