#!/bin/bash
# garnet-shard oracle: author the C recovery program, build it, and run it on
# the visible artifacts to produce /app/creds.txt. Never reads /tests.
set -eu

cat > /app/gullbreak.c <<'CC'
/* gullbreak - gull cipher subkey recovery for the garnet-shard incident */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define ROUNDS 3

static uint8_t rfunc(uint8_t r, uint8_t k_lo, uint8_t k_hi) {
    uint8_t t = (uint8_t)(r ^ k_lo);
    uint8_t u = (uint8_t)(t * 0xB7);
    u = (uint8_t)((u << 1) | (u >> 7));   /* rotl 1 */
    return (uint8_t)(u ^ (uint8_t)(k_hi + r));
}

static uint16_t gull_encrypt(uint16_t p, uint16_t k) {
    uint8_t l = (uint8_t)(p >> 8), r = (uint8_t)(p & 0xFF);
    uint8_t k_lo = (uint8_t)(k & 0xFF), k_hi = (uint8_t)(k >> 8);
    for (int i = 0; i < ROUNDS; i++) {
        uint8_t nl = r, nr = (uint8_t)(l ^ rfunc(r, k_lo, k_hi));
        l = nl; r = nr;
    }
    return (uint16_t)((l << 8) | r);
}

static uint16_t gull_decrypt(uint16_t c, uint16_t k) {
    uint8_t l = (uint8_t)(c >> 8), r = (uint8_t)(c & 0xFF);
    uint8_t k_lo = (uint8_t)(k & 0xFF), k_hi = (uint8_t)(k >> 8);
    for (int i = 0; i < ROUNDS; i++) {
        uint8_t nl = (uint8_t)(r ^ rfunc(l, k_lo, k_hi)), nr = l;
        l = nl; r = nr;
    }
    return (uint16_t)((l << 8) | r);
}

static int hexval(int c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/* parse one hex token of up to 4 digits starting at s; advance *ps.
   returns value or -1 on malformed. */
static long parse_hex_token(const char *s, const char **ps) {
    long v = 0;
    int n = 0;
    while (s[n] && hexval((unsigned char)s[n]) >= 0) {
        v = v * 16 + hexval((unsigned char)s[n]);
        n++;
        if (n > 4) return -1;
    }
    if (n == 0) return -1;
    *ps = s + n;
    return v;
}

/* load pairs: returns count (>=1) or -1 on unreadable/malformed */
static int load_pairs(const char *path, uint16_t *pt, uint16_t *ct, int max) {
    FILE *fh = fopen(path, "r");
    if (!fh) return -1;
    char line[512];
    int cnt = 0;
    while (fgets(line, sizeof line, fh)) {
        const char *s = line;
        while (*s && isspace((unsigned char)*s)) s++;
        if (*s == '\0' || *s == '#') continue;
        long p = parse_hex_token(s, &s);
        if (p < 0 || p > 0xFFFF) { fclose(fh); return -1; }
        while (*s && isspace((unsigned char)*s)) s++;
        if (*s == ',') { s++; while (*s && isspace((unsigned char)*s)) s++; }
        long c = parse_hex_token(s, &s);
        if (c < 0 || c > 0xFFFF) { fclose(fh); return -1; }
        while (*s && isspace((unsigned char)*s)) s++;
        if (*s != '\0' && *s != '\n' && *s != '\r' && *s != '#') { fclose(fh); return -1; }
        if (cnt >= max) { fclose(fh); return -1; }
        pt[cnt] = (uint16_t)p;
        ct[cnt] = (uint16_t)c;
        cnt++;
    }
    fclose(fh);
    return cnt >= 1 ? cnt : -1;
}

uint32_t recover_gull_key(const char *pairs_path) {
    uint16_t pt[256], ct[256];
    int n = load_pairs(pairs_path, pt, ct, 256);
    if (n < 0) return 0;
    for (uint32_t k = 0; k <= 0xFFFF; k++) {
        int ok = 1;
        for (int i = 0; i < n; i++) {
            if (gull_encrypt(pt[i], (uint16_t)k) != ct[i]) { ok = 0; break; }
        }
        if (ok) return k;
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <pairs.txt> <target.hex>\n", argv[0]);
        return 2;
    }
    uint32_t key = recover_gull_key(argv[1]);
    /* parse target blocks */
    FILE *fh = fopen(argv[2], "r");
    if (!fh) { fprintf(stderr, "cannot open target\n"); return 2; }
    printf("key=%u\n", key);
    printf("plain=");
    char line[512];
    while (fgets(line, sizeof line, fh)) {
        const char *s = line;
        while (*s) {
            while (*s && (isspace((unsigned char)*s) || *s == ',')) s++;
            if (!*s || *s == '#') break;
            long v = parse_hex_token(s, &s);
            if (v < 0 || v > 0xFFFF) { fclose(fh); printf("\n"); return 2; }
            uint16_t dec = gull_decrypt((uint16_t)v, (uint16_t)key);
            printf("%04x", dec);
        }
    }
    fclose(fh);
    printf("\n");
    return 0;
}
CC

gcc -O2 -o /app/gullbreak /app/gullbreak.c
gcc -O2 -shared -fPIC -o /tmp/gullbreak.so /app/gullbreak.c

# run the recovery for real on the provided artifacts
/app/gullbreak /app/artifacts/pairs.txt /app/artifacts/target.hex
KEY_LINE="$(/app/gullbreak /app/artifacts/pairs.txt /app/artifacts/target.hex | sed -n 's/^key=//p')"
PLAIN_LINE="$(/app/gullbreak /app/artifacts/pairs.txt /app/artifacts/target.hex | sed -n 's/^plain=//p')"
{
  echo "key=$KEY_LINE"
  echo "plain=$PLAIN_LINE"
} > /app/creds.txt

echo "solve.sh done"
ls -l /app/gullbreak.c /app/gullbreak /app/creds.txt
