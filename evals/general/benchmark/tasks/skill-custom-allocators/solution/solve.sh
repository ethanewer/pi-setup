#!/bin/bash
set -euo pipefail
cat > /app/project/arena.c <<'C'
#include "arena.h"
#include <stdalign.h>
void arena_init(Arena *a, void *pool, size_t capacity) {
    a->pool = pool;
    a->capacity = capacity;
    a->offset = 0;
}
void *arena_alloc(Arena *a, size_t n) {
    size_t aligned = (n + 7u) & ~((size_t)7u);
    if (a->offset + aligned > a->capacity) {
        return NULL;
    }
    void *p = (unsigned char *)a->pool + a->offset;
    a->offset += aligned;
    return p;
}
size_t arena_used(const Arena *a) { return a->offset; }
void arena_reset(Arena *a) { a->offset = 0; }
C
cd /app/project
gcc -std=c11 -Wall -Wextra arena.c main.c -o arena_test
./arena_test > /app/result.txt