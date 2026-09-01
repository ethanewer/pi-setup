/*
 * Garnet Vault -- activation code checker (build 2031.4)
 *
 * Usage: ./vault <PROFILE> <CODE>
 * Prints "ACCEPT <PROFILE>" when CODE is a valid activation code for
 * PROFILE, "REJECT" otherwise.
 *
 * The activation constants below are stored obfuscated (XOR 0x5A5A5A5A)
 * so they do not appear as plaintext in release images.
 */
#include <stdio.h>
#include <string.h>
#include <stdint.h>

#define NMASK 0x5A5A5A5Au
#define CODELEN 16

static const char ALPH[] = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

typedef struct {
    const char *id;
    int         enabled;   /* profiles disabled in this build reject everything */
    uint32_t    seed;      /* chain seed */
    uint32_t    oa;        /* obfuscated multiplier  */
    uint32_t    ob;        /* obfuscated increment   */
    uint32_t    oc;        /* obfuscated checksum multiplier */
    uint32_t    ohash;     /* obfuscated rolling-hash target */
    uint32_t    ochk;      /* obfuscated checksum target     */
} prof;

static const prof TABLE[] = {
    {"A", 1, 0x00002F1Au, 0x1B9C1437u, 0x5A5A3A43u, 0x5A5A598Bu, 0x2A6E9BC0u, 0x5A5A599Fu},
    {"B", 1, 0x0001B7C3u, 0x5B00146Fu, 0x5A5A792Fu, 0x5A5A598Bu, 0x44800DBCu, 0x5A5A58A7u},
    {"C", 1, 0x0000C0DEu, 0x5A5B5797u, 0x5A5A2033u, 0x5A5A598Bu, 0x0AA26DFDu, 0x5A5A5978u},
    {"D", 0, 0x00005EEDu, 0x5A5919A7u, 0x5A7CC499u, 0x5A5A598Bu, 0x50278444u, 0x5A5A5B0Cu},
};
#define NTABLE ((int)(sizeof(TABLE) / sizeof(TABLE[0])))

static uint32_t unmask(uint32_t x)
{
    return x ^ NMASK;
}

/* 32-bit rolling hash over the code characters (djbv2-style). */
static uint32_t roll(uint32_t h, const char *s, int n)
{
    int i;
    for (i = 0; i < n; i++)
        h = h * 31u + (uint32_t)(unsigned char)s[i];
    return h;
}

static int check(const prof *p, const char *code)
{
    uint32_t state, h, sum;
    int i;

    if (!p->enabled)
        return 0;
    if (strlen(code) != CODELEN)
        return 0;

    state = p->seed;
    sum = 0;
    for (i = 0; i < CODELEN; i++) {
        const char *q = strchr(ALPH, code[i]);
        uint32_t v, want;
        if (q == NULL)
            return 0;
        v = (uint32_t)(q - ALPH);
        sum += v;
        /* one step of the per-character chain */
        state = (state * unmask(p->oa) + unmask(p->ob) + 0x9E3779B9u * (uint32_t)i)
                & 0x7FFFFFFFu;
        want = (state >> 13) & 31u;
        if (v != want)
            return 0;
    }

    if ((sum * unmask(p->oc)) % 997u != unmask(p->ochk))
        return 0;
    h = roll(5381u, code, CODELEN);
    return h == unmask(p->ohash);
}

int main(int argc, char **argv)
{
    int i;

    if (argc != 3) {
        fprintf(stderr, "usage: %s <PROFILE> <CODE>\n", argv[0]);
        return 2;
    }
    for (i = 0; i < NTABLE; i++) {
        if (strcmp(TABLE[i].id, argv[1]) == 0) {
            if (check(&TABLE[i], argv[2]))
                printf("ACCEPT %s\n", TABLE[i].id);
            else
                printf("REJECT\n");
            return 0;
        }
    }
    fprintf(stderr, "unknown profile '%s'\n", argv[1]);
    return 2;
}
