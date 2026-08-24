#include <stdio.h>
#include "arena.h"
static unsigned char pool[65536];
int main(void) {
    Arena a;
    arena_init(&a, pool, sizeof(pool));
    void *p1 = arena_alloc(&a, 8);
    void *p2 = arena_alloc(&a, 24);
    void *p3 = arena_alloc(&a, 1);
    if (!p1 || !p2 || !p3) { printf("FAIL_NULL\n"); return 0; }
    if (((size_t)p1 % 8) != 0) { printf("FAIL_ALIGN\n"); return 0; }
    if (arena_used(&a) != 40) { printf("FAIL_USED\n"); return 0; }
    arena_reset(&a);
    if (arena_used(&a) != 0) { printf("FAIL_RESET\n"); return 0; }
    /* Over-allocation beyond remaining capacity must fail with NULL. */
    Arena b;
    unsigned char small[20];
    arena_init(&b, small, sizeof(small));
    if (arena_alloc(&b, 17) != NULL) { printf("FAIL_OVERALLOC\n"); return 0; }
    void *q = arena_alloc(&b, 16);
    if (!q) { printf("FAIL_FIT\n"); return 0; }
    if (arena_used(&b) != 16) { printf("FAIL_USED2\n"); return 0; }
    printf("ALLOC_OK\n");
    return 0;
}