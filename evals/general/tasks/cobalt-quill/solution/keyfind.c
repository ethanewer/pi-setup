#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>

/* orca cipher: C = mix(P ^ K), 32-bit block/key */
#define MASK 0xFFFFFFFFu
#define RMUL 0x2545F491u
#define RMUL_INV 0x41444C71u

static uint32_t mix(uint32_t x) {
    x ^= x >> 15;
    x *= RMUL;
    x ^= x << 7;
    return x & MASK;
}

static uint32_t unmix(uint32_t y) {
    uint32_t x = y ^ (y << 7) ^ (y << 14) ^ (y << 21) ^ (y << 28);
    x &= MASK;
    x *= RMUL_INV;
    x ^= x >> 15;
    x ^= x >> 30;
    return x & MASK;
}

/* parse one hex token with optional 0x/0X prefix, case-insensitive; returns 1 on success */
static int parse_hex32(const char *tok, uint32_t *out) {
    if (tok[0] == '0' && (tok[1] == 'x' || tok[1] == 'X')) tok += 2;
    if (!isxdigit((unsigned char)tok[0])) return 0;
    uint64_t v = 0;
    int ndig = 0;
    for (; tok[0]; tok++) {
        if (!isxdigit((unsigned char)tok[0])) return 0;
        if (++ndig > 8) return 0;
        int c = tok[0];
        int d = (c <= '9') ? c - '0' : (tolower(c) - 'a' + 10);
        v = (v << 4) | (uint64_t)d;
    }
    *out = (uint32_t)v;
    return 1;
}

static uint32_t recover_key_impl(const char *pairs_path) {
    FILE *fh = fopen(pairs_path, "r");
    if (!fh) return 0;
    char line[1024];
    int have_key = 0;
    uint32_t key = 0;
    while (fgets(line, sizeof line, fh)) {
        char *a = NULL, *b = NULL, *p = line;
        /* tokenize on whitespace/commas, skip # comments */
        while (*p) {
            if (*p == '#') break;
            if (isspace((unsigned char)*p) || *p == ',') { p++; continue; }
            if (!a) a = p; else if (!b) b = p; else break;
            while (*p && !isspace((unsigned char)*p) && *p != ',') p++;
        }
        if (!a || !b) continue; /* blank / comment / single-token line */
        uint32_t P, C;
        if (!parse_hex32(a, &P) || !parse_hex32(b, &C)) continue;
        uint32_t k = unmix(C) ^ P;
        if (have_key && k != key) { fclose(fh); return 0; }
        key = k;
        have_key = 1;
    }
    fclose(fh);
    return have_key ? key : 0;
}

uint32_t recover_key(const char *pairs_path) {
    if (!pairs_path) return 0;
    return recover_key_impl(pairs_path);
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: keyfind <pairs.txt> <target.hex>\n");
        return 2;
    }
    uint32_t k = recover_key(argv[1]);
    /* read target tokens */
    FILE *fh = fopen(argv[2], "r");
    if (!fh) {
        fprintf(stderr, "keyfind: cannot open %s\n", argv[2]);
        return 2;
    }
    char tok[128];
    printf("key=%u\n", (unsigned)k);
    printf("plain=");
    while (fscanf(fh, "%127s", tok) == 1) {
        uint32_t C;
        if (parse_hex32(tok, &C))
            printf("%08x", (unsigned)(unmix(C) ^ k));
    }
    printf("\n");
    fclose(fh);
    return 0;
}
