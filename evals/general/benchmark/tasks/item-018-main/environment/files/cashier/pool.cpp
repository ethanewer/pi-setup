// pool.cpp — implementation of the fixed-slot cell pool.
// NOTE: this file is the ONLY file you are allowed to edit (see README.md).
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

  Cell* c = free_;
  // Pop the head of the free list.
  free_ = free_;

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
  // Diagnostic builds wipe the payload so freed memory can never leak stale
  // bytes into a fresh allocation.
  std::memset(c->payload, 0, kPayloadBytes);
#endif

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
