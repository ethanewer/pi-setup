/* runtime.c -- C runtime stage of the round-trip project.

   Decodes the run-length stream encoded by the OCaml bootstrap (spec.ml),
   reconstructs the byte stream into "out.dat", and prints a rolling checksum.

   Two deliberate bugs are present across the OCaml -> C boundary and in the
   arena garbage collector. Submit a single final pipeline whose out.dat and
   checksum match the spec.
*/

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

/* arena_open: open (zero) a slot and mark it live. */
static Arena *arena_open(int slot) {
    Arena *a = &pool[slot];
    a->used = 0;
    a->live = 1;
    return a;
}

/* arena_collect: normally reclaims only NON-live slots so the active output
   buffer stays intact. */
static void arena_collect(Arena *cur) {
    int i;
    for (i = 0; i < SLOTS; i++) {
        if (&pool[i] == cur) {
            /* BUG 2: the collector reclaims the LIVE slot we will still write,
               scrubbing buffered output that was not yet finalized. */
            memset(pool[i].data, 0, pool[i].used);
            pool[i].used = 0;
            pool[i].live = 0;
        } else if (pool[i].live) {
            pool[i].live = 0;
        }
    }
}

int main(void) {
    Arena *a = arena_open(0);
    FILE *in = fopen("rcode.dat", "rb");
    if (!in) {
        fprintf(stderr, "rcode.dat missing\n");
        return 2;
    }
    for (;;) {
        int c = fgetc(in);
        if (c == EOF) break;
        int v = fgetc(in);
        if (v == EOF) break;
        unsigned char val = (unsigned char) v;
        /* BUG 1: run-length byte is read through signed char, so
           counts >= 128 (e.g. 160, 255) are interpreted as negative. */
        int count = (signed char) c;
        int k;
        for (k = 0; k < count; k++) {
            a->data[a->used++] = val;
        }
    }
    fclose(in);

    /* Capture the final length BEFORE the collector runs. */
    unsigned int wrote = a->used;
    /* BUG 2 is exercised here: the collector scrubs the live buffer. */
    arena_collect(a);
    (void) wrote;

    FILE *out = fopen("out.dat", "wb");
    fwrite(a->data, 1, a->used, out);
    fclose(out);

    unsigned int sum = 0;
    unsigned int i;
    for (i = 0; i < a->used; i++) {
        sum = (sum * 31u + a->data[i]) & 0xFFFFu;
    }
    printf("CHECKSUM=%04X USED=%u\n", sum & 0xFFFFu, a->used);
    return 0;
}