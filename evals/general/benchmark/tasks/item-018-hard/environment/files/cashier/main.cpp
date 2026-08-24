// main.cpp — "ledger" simulator that exercises the Pool allocator.
// IMMUTABLE (see README.md). Do not edit.
#include "pool.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

static constexpr int kMaxRows = 32;   // row ids 0..31
static constexpr int kPoolCells = 16; // pool capacity

// One ledger row lives in one pool cell.
struct Row {
  long long balance;
  unsigned char tag[16];  // contract: zeroed on alloc (see README.md)
};
static_assert(sizeof(Row) <= Pool::kPayloadBytes, "row must fit in a cell");

int main(int argc, char** argv) {
  const char* path = "cases.txt";
  if (argc >= 3 && std::strcmp(argv[1], "--input") == 0) path = argv[2];

  Pool pool(kPoolCells);
  Row* rows[kMaxRows] = {nullptr};

  FILE* f = std::fopen(path, "r");
  if (!f) {
    std::fprintf(stderr, "ledger: cannot open %s\n", path);
    return 2;
  }
  char buf[128];
  while (std::fgets(buf, sizeof buf, f)) {
    char op = '\0';
    int a = -1;
    long long v = 0;
    if (std::sscanf(buf, " %c %d %lld", &op, &a, &v) < 1) continue;
    switch (op) {
      case 'N': {  // N <rowid> : allocate a live row
        if (a < 0 || a >= kMaxRows) break;
        if (rows[a] != nullptr) break;
        rows[a] = static_cast<Row*>(pool.alloc(sizeof(Row)));
        break;
      }
      case 'W': {  // W <rowid> <amount> : credit the row
        if (a < 0 || a >= kMaxRows) break;
        if (rows[a] != nullptr) rows[a]->balance += v;
        break;
      }
      case 'F': {  // F <rowid> : free the row (no-op if already dead)
        if (a < 0 || a >= kMaxRows) break;
        if (rows[a] == nullptr) break;
        pool.dealloc(rows[a]);
        rows[a] = nullptr;
        break;
      }
      case 'T': {  // T <rowid> : print balance + hex tag of the row
        if (a < 0 || a >= kMaxRows) break;
        if (rows[a] != nullptr) {
          std::printf("%lld ", rows[a]->balance);
          const unsigned char* t = rows[a]->tag;
          for (int i = 0; i < 16; ++i) std::printf("%02x", t[i]);
          std::printf("\n");
        }
        break;
      }
      case 'S': {  // S : print total balance across live rows
        long long total = 0;
        for (int i = 0; i < kMaxRows; ++i) {
          if (rows[i] != nullptr) total += rows[i]->balance;
        }
        std::printf("%lld\n", total);
        break;
      }
      default:
        break;
    }
  }
  std::fclose(f);

  std::printf("LIVE %zu/%zu\n", pool.live(), pool.capacity());
  return 0;
}