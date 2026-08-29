/* flint GC sweep driver — independent reference verifier for /app/vm/sweep.c.
 * Compares the agent's sweep() against a brute-force reference over a suite
 * of adversarial fixed bitmaps plus many seeded random heaps, and checks the
 * RLE invariants directly (no run past the heap, no run covering a live word,
 * contiguous free words coalesced). Exits 0 only when every case matches.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sweep.h"

#define MAX 8192

static int g_fail = 0;

static void fail(const char *why, unsigned long seed, size_t size) {
    if (g_fail < 20) fprintf(stderr, "SWEEP-MISMATCH seed=%lu size=%zu: %s\n", seed, size, why);
    g_fail++;
}

/* brute-force reference: maximal runs of !live words */
static int ref_sweep(const unsigned char *l, size_t sz, run_t *out) {
    int n = 0;
    size_t i = 0;
    while (i < sz) {
        if (l[i]) { i++; continue; }
        size_t s = i;
        while (i < sz && !l[i]) i++;
        out[n].start = s; out[n].len = i - s; n++;
    }
    return n;
}

/* direct invariant check on agent output */
static void check_invariants(const unsigned char *l, size_t sz, const run_t *out, int n, unsigned long seed) {
    for (int k = 0; k < n; k++) {
        unsigned long s = out[k].start, len = out[k].len;
        if (len == 0 || s + len > sz)
            fail("run extends past heap or has zero length", seed, sz);
        for (size_t w = s; w < s + len && w < sz; w++)
            if (l[w]) fail("run covers a live word", seed, sz);
    }
    /* contiguous free words must be coalesced into a single run */
    size_t i = 0;
    int k = 0;
    while (i < sz && k < n) {
        if (l[i]) { i++; continue; }
        if (out[k].start != i) { fail("runs not ordered/contiguous", seed, sz); return; }
        i += out[k].len; k++;
    }
    /* after the last run, only live words may remain */
    while (i < sz) { if (!l[i]) { fail("missing free run", seed, sz); return; } i++; }
    if (k != n) fail("trailing leftover check", seed, sz);
}

static int check(unsigned char *l, size_t sz, unsigned long seed) {
    run_t ref[MAX], got[MAX];
    int nr = ref_sweep(l, sz, ref);
    int ng = sweep(l, sz, got, MAX);
    if (nr != ng) { fail("run-count differs", seed, sz); }
    if (nr != 0 && memcmp(ref, got, sizeof(run_t) * (nr < ng ? nr : ng)) != 0)
        fail("run sequence differs", seed, sz);
    check_invariants(l, sz, got, ng, seed);
    return ng;
}

int main(void) {
    unsigned char l[512];
    size_t sz;

    /* --- fixed adversarial cases --- */
    sz = 1;  l[0] = 0;                     check(l, sz, 901);
    sz = 1;  l[0] = 1;                     check(l, sz, 902);
    sz = 8;  memset(l, 1, 8);              check(l, sz, 903);
    sz = 8;  memset(l, 0, 8);              check(l, sz, 904);
    sz = 16; memset(l, 1, 16); l[5] = 0;   check(l, sz, 905);   /* single free mid */
    sz = 16; memset(l, 0, 16); l[5] = 1;   check(l, sz, 906);   /* single live mid */
    sz = 16; memset(l, 1, 16); for (int i=0;i<16;i+=2) l[i]=0;  check(l, sz, 907); /* alternat */
    sz = 16; memset(l, 0, 16); l[0]=1; l[15]=1;                  check(l, sz, 908); /* free ends */
    sz = 40; memset(l, 1, 40); l[3]=0; l[4]=0; l[39]=0;          check(l, sz, 909);
    sz = 8;  memset(l, 0, 8);  l[2]=1; l[3]=1; l[4]=1;           check(l, sz, 910);
    sz = 64; memset(l, 0, 64);                                    check(l, sz, 911); /* all free */

    /* --- seeded random heaps --- */
    unsigned long seed = 123456789;
    for (int t = 0; t < 400; t++) {
        seed = seed * 6364136223846793005ULL + 1442695040888963407ULL;
        sz = 16 + (seed % 257);
        for (size_t i = 0; i < sz; i++) {
            seed = seed * 6364136223846793005ULL + 1442695040888963407ULL;
            l[i] = (seed & 7) == 0;      /* ~1/8 of words live */
        }
        check(l, sz, seed);
    }
    /* denser live-set random heaps */
    for (int t = 0; t < 200; t++) {
        seed = seed * 6364136223846793005ULL + 1442695040888963407ULL;
        sz = 8 + (seed % 129);
        for (size_t i = 0; i < sz; i++) {
            seed = seed * 6364136223846793005ULL + 1442695040888963407ULL;
            l[i] = (seed & 1) == 0;
        }
        check(l, sz, seed);
    }

    if (g_fail == 0) { printf("SWEEP-OK\n"); return 0; }
    fprintf(stderr, "sweep driver: %d mismatches\n", g_fail);
    return 1;
}
