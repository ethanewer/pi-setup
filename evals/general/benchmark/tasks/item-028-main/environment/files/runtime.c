/* runtime.c -- the C runtime half of the project.

   Decodes the RLE stream produced by the OCaml bootstrap (spec.ml), writes the
   reconstructed byte stream to "out.dat", and prints a rolling checksum.

   There is a deliberate build bug: the decoded order / byte stream does not yet
   match the spec. Debug the boundary between the OCaml bootstrap and this C
   runtime and apply the smallest correct source change.
*/

#include <stdio.h>

/* ------------------- minimal arena / memory administration -------------- */
#define NSLOTS 4
#define CAP (1 << 20)

typedef struct {
    unsigned char data[CAP];
    unsigned int used;
    unsigned int live;
} Arena;

static Arena pool[NSLOTS];

/* Open (reset) an arena slot. Only slot 0 is used to accumulate the whole
   decoded output. */
static Arena* arena_open(int idx) {
    pool[idx].used = 0;
    pool[idx].live = 1;
    return &pool[idx];
}

/* Arena sweep: release every non-live slot back to the pool.  Slot 0 is the
   active output accumulator and must remain live. */
static void arena_sweep(void) {
    int i;
    for (i = 1; i < NSLOTS; i++) {
        pool[i].live = 0;   /* freed */
    }
}

/* ------------------------------------------------------------------------- */
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
        int count = (signed char) c;              /* BUG: reads count signed */
        int k;
        for (k = 0; k < count; k++) {
            a->data[a->used] = val;
            a->used++;
        }
    }
    fclose(in);

    arena_sweep(); /* after decoding; must not release the active output */

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