#!/bin/bash
# Oracle solution for item-028-hard.
# Replace runtime.c with a corrected version (both fixes), rebuild, run the
# round-trip + regression suite.
set -euo pipefail
cd /app

cat > runtime.c <<'RUNT'
#include <stdio.h>
#include <string.h>

#define SLOTS 16
#define CAP (1 << 20)

typedef struct {
    unsigned char data[CAP];
    unsigned int used;
    unsigned char live;
} Arena;

static Arena pool[SLOTS];

static Arena *arena_open(int slot) {
    Arena *a = &pool[slot];
    a->used = 0;
    a->live = 1;
    return a;
}

/* Correct collector: reclaims only NON-live slots; the active output buffer
   is still referenced and remains live until after it has been written. */
static void arena_collect(Arena *cur) {
    int i;
    for (i = 0; i < SLOTS; i++) {
        if (&pool[i] == cur) continue; /* keep the referenced/live object */
        if (pool[i].live) {
            memset(pool[i].data, 0, pool[i].used);
            pool[i].used = 0;
            pool[i].live = 0;
        }
    }
}

int main(void) {
    Arena *a = arena_open(0);
    FILE *in = fopen("rcode.dat", "rb");
    if (!in) { fprintf(stderr, "rcode.dat missing\n"); return 2; }
    for (;;) {
        int c = fgetc(in);
        if (c == EOF) break;
        int v = fgetc(in);
        if (v == EOF) break;
        unsigned char val = (unsigned char) v;
        int count = (int)(unsigned char) c;   /* count byte is unsigned */
        int k;
        for (k = 0; k < count; k++) {
            a->data[a->used++] = val;
        }
    }
    fclose(in);

    unsigned int wrote = a->used;

    FILE *out = fopen("out.dat", "wb");
    fwrite(a->data, 1, a->used, out);
    fclose(out);

    /* Collect only after the live buffer has been fully consumed. */
    arena_collect(a);

    unsigned int sum = 0;
    unsigned int i;
    for (i = 0; i < wrote && i < a->used; i++) {
        sum = (sum * 31u + a->data[i]) & 0xFFFFu;
    }
    printf("CHECKSUM=%04X USED=%u\n", sum & 0xFFFFu, wrote);
    return 0;
}
RUNT

# regen the spec stream (deterministic layout)
make clean
make runtime
make rcode.dat
make check
python3 verify.py

python3 -m pytest /app -q

echo "SOLVED"