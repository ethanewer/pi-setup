#!/bin/bash
# Oracle solution for item-018-hard.
# Fixes the three allocator defects in pool.cpp (the ONLY editable file),
# rebuilds both modes, confirms identical & correct behavior on the visible
# case, and writes the required isolation artifact.
set -euo pipefail
cd /app/cashier

# Defects in the shipped pool.cpp (all confined to pool.cpp):
#   1. alloc(): free-list pop is a no-op (free_ = free_) -> every alloc
#      returns the same head cell (double allocation, double counting).
#   2. alloc(): the payload zero-fill (contract: no stale bytes) is inside
#      #ifdef DEBUG_CHECKPOOL, so only the debug build wipes reused cells.
#   3. dealloc(): the relink statements are in the wrong order
#      (free_ = c; c->next = free_;) so every freed head cell points to
#      itself -> a later free+2-alloc sequence double-allocates the head.
cat > pool.cpp <<'CPP'
// pool.cpp — implementation of the fixed-slot cell pool (corrected).
#include "pool.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

void Pool::init() {
  mem_ = static_cast<Cell*>(std::calloc(cells_, sizeof(Cell)));
  if (mem_ == nullptr) {
    std::fprintf(stderr, "POOLFATAL: arena allocation failed\n");
    std::abort();
  }
  for (std::size_t i = 0; i < cells_; ++i) {
    Cell* c = mem_ + i;
    c->magic = kMagicFree;
    c->next = (i + 1 < cells_) ? (mem_ + i + 1) : nullptr;
  }
  free_ = mem_;
  live_ = 0;
}

Pool::Pool(std::size_t cells) : mem_(nullptr), free_(nullptr), cells_(cells), live_(0) {
  init();
}

Pool::~Pool() { std::free(mem_); }

void* Pool::alloc(std::size_t n) {
#ifdef DEBUG_CHECKPOOL
  if (n > kPayloadBytes) {
    std::fprintf(stderr, "POOLFATAL: oversized alloc request %zu\n", n);
    std::abort();
  }
#endif
  if (free_ == nullptr) return nullptr;  // pool exhausted

  // Pop the head of the free list.
  Cell* c = free_;
  free_ = c->next;

#ifdef DEBUG_CHECKPOOL
  if (c->magic == kMagicAlloc) {
    std::fprintf(stderr, "POOLDIAG: double allocation! cell %td is already live\n",
                 c - mem_);
    std::abort();
  }
  if (c->magic != kMagicFree) {
    std::fprintf(stderr, "POOLDIAG: alloc of corrupt cell %td (magic=%08x)\n",
                 c - mem_, static_cast<unsigned>(c->magic));
    std::abort();
  }
#endif

  // Contract guarantee: stale bytes must never leak into a fresh allocation
  // (applies in BOTH build modes).
  std::memset(c->payload, 0, kPayloadBytes);

  c->magic = kMagicAlloc;
  ++live_;
  return c->payload;
}

void Pool::dealloc(void* p) {
  Cell* c = reinterpret_cast<Cell*>(static_cast<char*>(p) - offsetof(Cell, payload));
#ifdef DEBUG_CHECKPOOL
  if (c->magic != kMagicAlloc) {
    std::fprintf(stderr, "POOLDIAG: free of cell %td that is not live (magic=%08x)\n",
                 c - mem_, static_cast<unsigned>(c->magic));
    std::abort();
  }
#endif
  c->magic = kMagicFree;
  c->next = free_;   // relink the free list head (order matters)
  free_ = c;
  --live_;
}
CPP

make -s debug release

# Required isolation artifact: shortest failing prefix + per-mode evidence.
mkdir -p /app/isolation
cat > /app/isolation/repro.txt <<'OPS'
N 0
N 1
W 0 5
W 1 7
S
OPS
cat > /app/isolation/notes.txt <<'NOTES'
Evidence by build mode (pristine, before fixes):
- debug (-O0 -DDEBUG_CHECKPOOL): POOLDIAG double allocation, abort, exit!=0
  at the second N op (N 1): the allocator hands out the same head cell twice.
- release (-O2 -DNDEBUG): runs, exits 0, but the second S line is 46 instead
  of 18: rows 1 and 2 alias the same pool cell, so balances are double counted.
- A second divergence remains after fixing the pop: release reuses a freed
  cell without zeroing its payload (stale balance leaks into the new row).
- A third defect only shows on free-then-two-alloc patterns: dealloc relinks
  the head to itself, so a freed cell can be handed out twice.
First diverging line between release and the true ledger: S line 2 (46 vs 18).
NOTES

echo "solution build OK"
echo "debug:   $(./build/debug/cashier --input cases.txt | tr '\n' ' ')"
echo "release: $(./build/release/cashier --input cases.txt | tr '\n' ' ')"