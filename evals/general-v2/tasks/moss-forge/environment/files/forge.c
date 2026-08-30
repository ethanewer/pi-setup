/*
 * forge.c — fixed-size pool allocator for the forge bench.
 *
 * Public contract (relied upon by the protected driver main.c):
 *   void *forge_alloc(size_t n)  — returns a pointer to at least n writable
 *                                  bytes, or NULL only if no free block is
 *                                  big enough.
 *   void  forge_free(void *p)    — returns a block to the pool.
 *
 * Design: first-fit singly-linked free list threaded through block headers
 * over one static arena; allocation splits a big free block when the
 * remainder is itself useful.
 */
#include <stddef.h>
#include <stdint.h>

#define ARENA_SIZE (1 << 23) /* 8 MiB pool */
#define MIN_SPLIT 32         /* don't leave a remainder smaller than this */

typedef struct Block {
    size_t size;       /* payload bytes in this block */
    struct Block *next; /* free-list link (meaningful only while free) */
} Block;

#define BLOCK_HDR sizeof(Block)

static _Alignas(16) unsigned char arena[ARENA_SIZE];
static Block *free_list = NULL;
static int arena_ready = 0;

static void arena_init(void)
{
    Block *b = (Block *)arena;
    b->size = ARENA_SIZE - BLOCK_HDR;
    b->next = NULL;
    free_list = b;
    arena_ready = 1;
}

void *forge_alloc(size_t n)
{
    if (!arena_ready)
        arena_init();
    if (n == 0)
        n = 1;
    n = (n + 15u) & ~(size_t)15u; /* 16-byte alignment for payloads */

    Block **pp = &free_list;
    while (*pp) {
        Block *b = *pp;
        if (b->size >= n) {
            if (b->size >= n + BLOCK_HDR + MIN_SPLIT) {
                /* split: the remainder stays on the free list */
                Block *rem = (Block *)((unsigned char *)b + BLOCK_HDR + n);
                rem->size = b->size - n - BLOCK_HDR;
                b->size = n;
                *pp = rem;
            } else {
                /* take the whole block off the free list */
                *pp = b->next;
            }
            b->next = NULL;
            return (unsigned char *)b + BLOCK_HDR;
        }
        pp = &b->next;
    }
    return NULL;
}

void forge_free(void *p)
{
    if (!p)
        return;
    Block *b = (Block *)((unsigned char *)p - BLOCK_HDR);
    b->next = free_list;
    free_list = b;
}
