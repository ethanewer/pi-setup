#include "store.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct Rec {
    char *key;
    long total;
    struct Rec *next;
} Rec;

static Rec *g_head = NULL;      /* global record chain */
static int g_registered = 0;
static char *g_scratch = NULL;  /* global scratch buffer, freed by destructor */

static char *xstrdup(const char *s)
{
    size_t n = strlen(s) + 1;
    char *p = malloc(n);
    if (p) {
        memcpy(p, s, n);
    }
    return p;
}

/* The ONLY sanctioned release path for the global registry. Registered with
 * atexit() by store_init(). */
static void store_free(void)
{
    Rec *r = g_head;
    while (r) {
        Rec *n = r->next;
        free(r->key);
        free(r);
        r = n;
    }
    g_head = NULL;
    free(g_scratch);
    g_scratch = NULL;
}

void store_init(void)
{
    if (!g_registered) {
        atexit(store_free);
        g_registered = 1;
    }
    if (!g_scratch) {
        /* Global scratch allocation: makes any skipped-destructor path
         * observable to a leak checker even before the first record. */
        g_scratch = malloc(256);
        if (g_scratch) {
            g_scratch[0] = '\0';
        }
    }
}

void store_add(const char *key, long value)
{
    Rec *r;
    for (r = g_head; r; r = r->next) {
        if (strcmp(r->key, key) == 0) {
            r->total += value;
            return;
        }
    }
    r = malloc(sizeof *r);
    if (!r) {
        fprintf(stderr, "out of memory\n");
        exit(1);
    }
    r->key = xstrdup(key);
    if (!r->key) {
        fprintf(stderr, "out of memory\n");
        exit(1);
    }
    r->total = value;
    r->next = g_head;
    g_head = r;
}

static int cmp_rec(const void *a, const void *b)
{
    const Rec *const *x = a;
    const Rec *const *y = b;
    return strcmp((*x)->key, (*y)->key);
}

void store_report(long bad)
{
    size_t n = 0;
    size_t i;
    Rec *r;
    Rec **arr;

    for (r = g_head; r; r = r->next) {
        n++;
    }
    arr = malloc(n * sizeof *arr);
    if (n && !arr) {
        fprintf(stderr, "out of memory\n");
        exit(1);
    }
    for (r = g_head, i = 0; r; r = r->next, i++) {
        arr[i] = r;
    }
    qsort(arr, n, sizeof *arr, cmp_rec);
    for (i = 0; i < n; i++) {
        printf("tally:%s=%ld\n", arr[i]->key, arr[i]->total);
    }
    free(arr);
    printf("bad:%ld\n", bad);
}
