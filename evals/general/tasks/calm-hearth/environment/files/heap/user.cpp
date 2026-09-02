// ---------------------------------------------------------------------------
// calm-hearth custom memory heap (editable source -- THIS IS THE FILE TO FIX)
//
// A minimal boundary-tag free-list allocator over a single static arena.
// main.cpp drives it with workloads and depends on these invariants:
//   * heap_alloc(n) returns a distinct n-byte writable region for every
//     request that fits in the arena, or NULL when the arena is exhausted.
//   * heap_free(p) returns the block at p to the (singly-linked, first-fit)
//     free list so its space may be handed out again by later heap_alloc.
//
// Release builds compile with -O2. Everything below is intentionally small.
// ---------------------------------------------------------------------------
#include <cstddef>
#include <cstdint>

// ARENA_SIZE must cover the total of all simultaneously-live allocations in
// every harness workload (do not reduce it): 16 MiB.
#define ARENA_SIZE (1u << 24)

static unsigned char arena[ARENA_SIZE];
static int built = 0;

struct Chunk {
    struct Chunk *next;        // next free chunk (meaningful only while free)
    size_t        size;        // usable bytes that follow this 16-byte header
};

static Chunk *free_head = nullptr;

static void build_arena() {
    Chunk *root = reinterpret_cast<Chunk *>(arena);
    root->next = nullptr;
    root->size = ARENA_SIZE - sizeof(Chunk);
    free_head = root;
    built = 1;
}

extern "C" void *heap_alloc(size_t size) {
    if (!built) build_arena();
    if (size == 0) size = 8;
    size = (size + 7u) & ~static_cast<size_t>(7u);   // 8-byte align

    for (Chunk **pp = &free_head; *pp; pp = &(*pp)->next) {
        Chunk *cur = *pp;
        if (cur->size >= size + sizeof(Chunk)) {
            // split: keep the tail remainder on the free list, hand out a head
            Chunk *rem = reinterpret_cast<Chunk *>(
                reinterpret_cast<uint8_t *>(cur) + sizeof(Chunk) + size);
            rem->next = cur->next;
            rem->size = cur->size - sizeof(Chunk) - size;
            *pp = rem;
            cur->size = size;
            return reinterpret_cast<uint8_t *>(cur) + sizeof(Chunk);
        } else if (cur->size >= size) {
            // exact (or near) fit: give the whole chunk
            *pp = cur->next;
            return reinterpret_cast<uint8_t *>(cur) + sizeof(Chunk);
        }
    }
    return nullptr;            // nothing big enough free
}

extern "C" void heap_free(void *p) {
    if (!p) return;
    Chunk *n = reinterpret_cast<Chunk *>(
        reinterpret_cast<uint8_t *>(p) - sizeof(Chunk));
    // NOTE: this is the buggy line. The recovered block is never re-linked
    // into the free list, so a request that should reuse released space finds
    // nothing and heap_alloc returns NULL -> main.cpp dereferences NULL.
    (void)n;  // <-- BUG: block is dropped instead of returned to the free list
}