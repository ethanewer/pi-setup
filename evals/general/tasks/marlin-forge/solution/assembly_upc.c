/* UPC-style shared-memory parallel assembly over pthreads.
 *
 * One shared heap (a single malloc'd long array, one cell per item) is filled
 * in parallel by num_threads worker threads, each owning a contiguous slice.
 * Each thread writes its own worker_<r>.dat file in the working directory.
 *
 * Usage: agen <num_threads> <total_items>
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

#define NROUNDS 4

static long g_items;            /* total_items */
static long g_threads;          /* num_threads */
static long *g_heap;            /* the shared heap: one cell per item */
static long *g_slice_sum;       /* per-thread slice sums */
static long *g_slice_max;       /* per-thread slice maxima */

static long value_of(long i) {
    return (i * 4453L + 911L) % 65521L;
}

static long slice_lo(long r) { return (g_items * r) / g_threads; }
static long slice_hi(long r) { return (g_items * (r + 1)) / g_threads; }

static void *worker(void *argp) {
    long r = (long)(intptr_t)argp;
    long lo = slice_lo(r), hi = slice_hi(r);
    long sum = 0, mx = 0, i;

    /* fill this thread's slice of the shared heap */
    for (i = lo; i < hi; i++) {
        long v = value_of(i);
        g_heap[i] = v;
        sum += v;
        if (i == lo || v > mx) mx = v;
    }
    g_slice_sum[r] = sum;
    g_slice_max[r] = mx;

    /* write this thread's own output file */
    char name[64];
    snprintf(name, sizeof(name), "worker_%ld.dat", r);
    FILE *f = fopen(name, "w");
    if (!f) {
        fprintf(stderr, "agen: cannot open %s\n", name);
        return NULL;
    }
    fprintf(f, "worker=%ld\n", r);
    fprintf(f, "span=%ld:%ld\n", lo, hi);
    fprintf(f, "sum=%ld\n", sum);
    fprintf(f, "max=%ld\n", mx);
    fprintf(f, "valid=true\n");
    fclose(f);
    return NULL;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <num_threads> <total_items>\n", argv[0]);
        return 3;
    }
    char *end1 = NULL, *end2 = NULL;
    long nt = strtol(argv[1], &end1, 10);
    long it = strtol(argv[2], &end2, 10);
    if (end1 == argv[1] || *end1 != '\0' || end2 == argv[2] || *end2 != '\0'
        || nt < 1 || it < 0) {
        fprintf(stderr, "usage: %s <num_threads> <total_items>\n", argv[0]);
        return 3;
    }
    g_threads = nt;
    g_items = it;

    g_heap = (long *)malloc(sizeof(long) * (size_t)(it > 0 ? it : 1));
    g_slice_sum = (long *)calloc((size_t)nt, sizeof(long));
    g_slice_max = (long *)calloc((size_t)nt, sizeof(long));
    if (!g_heap || !g_slice_sum || !g_slice_max) {
        fprintf(stderr, "agen: out of memory\n");
        return 1;
    }

    pthread_t *tids = (pthread_t *)malloc(sizeof(pthread_t) * (size_t)nt);
    long r;
    for (r = 0; r < nt; r++) {
        if (pthread_create(&tids[r], NULL, worker, (void *)(intptr_t)r) != 0) {
            fprintf(stderr, "agen: pthread_create failed\n");
            return 1;
        }
    }
    long grand = 0;
    for (r = 0; r < nt; r++) {
        pthread_join(tids[r], NULL);
        grand += g_slice_sum[r];
    }

    /* global consistency check against a serial reference total */
    long want = 0, i;
    for (i = 0; i < it; i++) want += value_of(i);
    if (grand != want) {
        fprintf(stderr, "agen: grand total %ld != serial total %ld\n", grand, want);
        return 1;
    }

    free(tids); free(g_slice_sum); free(g_slice_max); free(g_heap);
    return 0;
}
