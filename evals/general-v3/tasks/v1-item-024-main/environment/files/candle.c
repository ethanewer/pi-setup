/* candle.c — encryption oracle for item-024-main.
 *
 * A small 16-bit block cipher with a FEAL-like Feistel round function
 * (addition/XOR/rotate + an 8-bit substitution).  The 16-bit key is injected
 * at build time via the ORACLE_KEY macro and is NOT revealed by this source:
 * the real value lives only in the compiled binary (set by the Dockerfile).
 *
 * Usage:
 *   candle enc <hex2>     print encryption of the 16-bit plaintext (hex4)
 *   candle challenge      print the sealed challenge ciphertext (hex4)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef ORACLE_KEY
#define ORACLE_KEY 0x0000 /* unused default; the Dockerfile overrides this */
#endif

static unsigned char S(unsigned char y) {
    return (unsigned char)((y * 7u + 3u) & 0xFFu);
}

static unsigned char subkey(int r) {
    return (unsigned char)(((ORACLE_KEY + (unsigned int)(r * 17)) & 0xFFu) ^ ((ORACLE_KEY >> 8) & 0xFFu));
}

static unsigned short enc(unsigned short P) {
    unsigned int L = (P >> 8) & 0xFFu, R = P & 0xFFu;
    int r;
    for (r = 0; r < 6; r++) {
        unsigned char f = S((unsigned char)(R ^ subkey(r)));
        unsigned int nL = R;
        unsigned int nR = (L ^ f) & 0xFFu;
        L = nL;
        R = nR;
    }
    return (unsigned short)(((L << 8) | R) & 0xFFFFu);
}

static unsigned short hex16(const char *s) {
    unsigned long v = strtoul(s, NULL, 16);
    return (unsigned short)(v & 0xFFFFu);
}

int main(int argc, char **argv) {
    if (argc >= 3 && strcmp(argv[1], "enc") == 0) {
        unsigned short p = hex16(argv[2]);
        printf("%04X\n", enc(p));
        return 0;
    }
    if (argc >= 2 && strcmp(argv[1], "challenge") == 0) {
        unsigned short p = 0x4F4B; /* secret challenge plaintext, 'OK' */
        printf("%04X\n", enc(p));
        return 0;
    }
    fprintf(stderr, "usage: candle enc <hex2> | candle challenge\n");
    return 2;
}