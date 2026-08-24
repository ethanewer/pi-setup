#!/bin/bash
# Oracle solution for item-018-main.
# Fixes pool.cpp (the ONLY editable file) so both build modes behave identically
# and match the true ledger, then rebuilds and confirms parity.
set -euo pipefail
cd /app/cashier

# The pool.cpp in the image contains TWO real defects (both in pool.cpp only):
#   1. alloc()'s free-list pop is a no-op (free_ = free_), so every allocation
#      returns the same head cell -> double allocation / double counting.
#   2. The payload zero-fill (the allocator's "no stale bytes" guarantee) lives
#      behind #ifdef DEBUG_CHECKPOOL, so only the debug build wipes reused cells.
# We rewrite pool.cpp with both defects removed. Every other file is untouched.
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

  // Contract guarantee: stale bytes must never leak into a fresh allocation.
  // (Apply in BOTH modes, not just the diagnostic build.)
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
  c->next = free_;
  free_ = c;
  --live_;
}
CPP

# Build both modes and confirm they now agree AND match the true ledger.
make -s debug release
echo "solution build OK"

# Diagnostic summary (not required for reward):
echo "debug:   $(./build/debug/cashier --input cases.txt | tr '\n' ' ')"
echo "release: $(./build/release/cashier --input cases.txt | tr '\n' ' ')"