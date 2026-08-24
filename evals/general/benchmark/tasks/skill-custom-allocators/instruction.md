Under `/app/project` is a minimal C arena allocator. `arena.h` declares an `Arena` struct that tracks a backing byte pool, its capacity, and a bump offset. `arena.c` provides the implementation, but `arena_alloc()` is **unfinished** (it currently just returns NULL). `main.c` is a complete test harness.

Complete `arena_alloc()` in `/app/project/arena.c` so it implements a bump-pointer arena allocator:

- Allocate `n` bytes from the backing pool with 8-byte alignment (the returned pointer must be a multiple of 8).
- Advance the arena's `offset` by the aligned size.
- If the aligned `n` does not fit in the remaining capacity, return `NULL` and do not advance the offset.

Then compile and run the harness:
```
cd /app/project
gcc -std=c11 -Wall -Wextra arena.c main.c -o arena_test
./arena_test
```

When correct, the harness prints a single line `ALLOC_OK`. Do not modify `arena.h` or `main.c`. The verifier recompiles `arena.c` with its own harness and checks the output.