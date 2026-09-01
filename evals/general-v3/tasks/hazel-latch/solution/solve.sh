#!/bin/bash
# hazel-latch oracle: author the engine source, build the native binary, and
# drive it through the external launcher on the sample session.
set -eu

mkdir -p /app/src /app/bin

cat > /app/src/latch_engine.c <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>

#define MAXN 1000000

static uint32_t crc_table[256];

static void crc_init(void) {
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int k = 0; k < 8; k++)
            c = (c & 1u) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
        crc_table[i] = c;
    }
}

static uint32_t crc32_buf(const char *buf, size_t len) {
    uint32_t c = 0xFFFFFFFFu;
    for (size_t i = 0; i < len; i++)
        c = crc_table[(c ^ (unsigned char)buf[i]) & 0xFFu] ^ (c >> 8);
    return c ^ 0xFFFFFFFFu;
}

static int fail(const char *msg) {
    fprintf(stderr, "latch-engine: %s\n", msg);
    return 2;
}

int main(int argc, char **argv) {
    crc_init();

    if (argc == 2 && strcmp(argv[1], "--probe") == 0) {
        fputs("LATCH/1 READY\n", stdout);
        return 0;
    }

    if (argc == 3 && strcmp(argv[1], "--serve") == 0) {
        char *end = NULL;
        long long seed = strtoll(argv[2], &end, 10);
        if (end == argv[2] || (end && *end != '\0') ||
            seed < 0 || seed > 4294967295LL) {
            return fail("bad seed");
        }
        uint32_t s = (uint32_t)seed;

        char *payload = malloc((size_t)MAXN + 1);
        if (!payload) return fail("out of memory");

        char line[4096];
        while (fgets(line, sizeof line, stdin)) {
            char *p = line;
            while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
            if (*p == '\0') continue;          /* skip empty lines */
            char *q = p;
            if (*q == '+') q++;                /* tolerate leading '+' */
            char *d = q;
            while (isdigit((unsigned char)*d)) d++;
            if (d == q || (*d != '\0' && *d != '\n' && *d != '\r')) {
                free(payload);
                return fail("malformed request line");
            }
            long long n = strtoll(p, NULL, 10);
            if (n < 0 || n > MAXN) {
                free(payload);
                return fail("request out of range");
            }
            for (long long i = 0; i < n; i++) {
                s = s * 1664525u + 1013904223u;      /* 32-bit wraparound */
                payload[i] = (char)('a' + (int)((s >> 7) % 26u));
            }
            uint32_t crc = crc32_buf(payload, (size_t)n);
            printf("BEGIN %lld\n", n);
            fwrite(payload, 1, (size_t)n, stdout);
            fputc('\n', stdout);
            printf("END %08x\n", crc);
        }
        free(payload);
        return 0;
    }

    return fail("usage: latch-engine --probe | latch-engine --serve <seed>");
}
C

gcc -O2 -o /app/bin/latch-engine /app/src/latch_engine.c
chmod 0755 /app/bin/latch-engine

# boot probe
out="$(/app/bin/latch-engine --probe)"
[ "$out" = "LATCH/1 READY" ] || { echo "probe mismatch: $out"; exit 1; }

# drive through the external launcher on the sample session
node /app/launcher.mjs /app/samples/session.txt

echo "oracle success"
ls -l /app/bin/latch-engine /app/src/latch_engine.c
