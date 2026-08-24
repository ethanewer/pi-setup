#include "arena.h"
void arena_init(Arena *a, void *pool, size_t capacity) {
    a->pool = pool;
    a->capacity = capacity;
    a->offset = 0;
}
void *arena_alloc(Arena *a, size_t n) {
    /* Implement a bump-pointer arena allocator: return a pointer to n bytes
     * from the arena with 8-byte alignment, advancing the arena offset, or
     * return NULL if n bytes (after padding) do not fit in remaining capacity.
     * TODO(agent): implement this function. */
    return NULL;
}
size_t arena_used(const Arena *a) { return a->offset; }
void arena_reset(Arena *a) { a->offset = 0; }