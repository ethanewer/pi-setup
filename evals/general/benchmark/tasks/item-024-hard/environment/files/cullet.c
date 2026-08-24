/* cullet.c — the encryption oracle for item-024-hard.
 *
 * A 16-bit block cipher whose 32-bit key is split into two independent
 * 16-bit "lanes" (a high byte-lane and a low byte-lane) that are finally
 * mixed by XOR.  Used via a chosen-plaintext oracle; no decryption is ever
 * offered.  The key (KEY below) is compiled in and never printed.
 *
 * Usage:
 *   cullet enc <hex2>     print encryption of the 16-bit plaintext (hex4)
 *   cullet challenge      print the sealed challenge ciphertext (hex4)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define KEY 0x1C9E3A57UL

static unsigned char S(unsigned char y) {
    return (unsigned char)((y * 7u + 3u) & 0xFFu);
}
static unsigned char ROL(unsigned char x, int n) {
    n &= 7;
    return (unsigned char)(((x << n) | (x >> (8 - n))) & 0xFFu);
}

/* effective 8-bit subkeys: high lane (e0,e1), low lane (e2,e3) */
static unsigned char e0(void) { return (unsigned char)((KEY >> 24) & 0xFFu); }
static unsigned char e1(void) { return (unsigned char)((KEY >> 16) & 0xFFu); }
static unsigned char e2(void) { return (unsigned char)((KEY >> 8) & 0xFFu); }
static unsigned char e3(void) { return (unsigned char)(KEY & 0xFFu); }

static unsigned char laneA(unsigned char in) {
    return S((unsigned char)(S(ROL(in, 1) ^ e0()) ^ e1()));
}
static unsigned char laneB(unsigned char in) {
    return S((unsigned char)(S(ROL(in, 2) ^ e2()) ^ e3()));
}

static unsigned short enc(unsigned short P) {
    unsigned char a = laneA((unsigned char)((P >> 8) & 0xFFu));
    unsigned char b = laneB((unsigned char)(P & 0xFFu));
    return (unsigned short)(((a << 8) | (a ^ b)) & 0xFFFFu);
}

static unsigned short hex16(const char *s) {
    return (unsigned short)(strtoul(s, NULL, 16) & 0xFFFFu);
}

int main(int argc, char **argv) {
    if (argc >= 3 && strcmp(argv[1], "enc") == 0) {
        unsigned short p = hex16(argv[2]);
        printf("%04X\n", enc(p));
        return 0;
    }
    if (argc >= 2 && strcmp(argv[1], "challenge") == 0) {
        unsigned short p = 0x4F4B; /* 'OK' */
        printf("%04X\n", enc(p));
        return 0;
    }
    fprintf(stderr, "usage: cullet enc <hex2> | cullet challenge\n");
    return 2;
}