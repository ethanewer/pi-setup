#ifndef ARENA_H
#define ARENA_H
#include <stddef.h>
typedef struct Arena {
    void *pool;
    size_t capacity;
    size_t offset;
} Arena;
void arena_init(Arena *a, void *pool, size_t capacity);
void *arena_alloc(Arena *a, size_t n);
size_t arena_used(const Arena *a);
void arena_reset(Arena *a);
#endif