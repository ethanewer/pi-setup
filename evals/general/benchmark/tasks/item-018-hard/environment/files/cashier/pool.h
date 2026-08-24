// pool.h — fixed-slot cell pool used by the ledger simulator.
// INTERFACE ONLY. This file is part of the immutable boundary (see README.md).
#pragma once

#include <cstddef>
#include <cstdint>

// A 64-byte cell: 8-byte bookkeeping header + 56 bytes of usable payload.
// The pool hands out payload pointers; callers never see the header.
class Pool {
 public:
  static constexpr std::uint32_t kMagicAlloc = 0xC0ECu;
  static constexpr std::uint32_t kMagicFree = 0xDEADBEE5u;
  static constexpr std::size_t kCellBytes = 64u;
  static constexpr std::size_t kPayloadBytes = 48u;

  explicit Pool(std::size_t cells);
  ~Pool();

  // Returns a pointer to a freshly allocated cell's payload, or nullptr when
  // the pool has no free cells. n must be <= kPayloadBytes.
  void* alloc(std::size_t n);

  // Returns a cell previously handed out by alloc() back to the pool.
  void dealloc(void* p);

  std::size_t live() const { return live_; }
  std::size_t capacity() const { return cells_; }

 private:
  struct Cell {
    std::uint32_t magic;
    Cell* next;
    unsigned char payload[kPayloadBytes];
  };
  static_assert(sizeof(Cell) == kCellBytes, "cell layout");

  void init();
  Cell* mem_;        // arena (cells_ cells)
  Cell* free_;       // head of the LIFO free list
  std::size_t cells_;
  std::size_t live_;
};
