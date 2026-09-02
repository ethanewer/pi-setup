# moss-forge — repair the release-mode pool crash

The forge bench at `/app` compiles a metal-casting simulator against a small
**custom pool allocator**. The shipped `-O2` release build,
`/app/forgebench`, **segfaults** on the bench workload. Your job is to
diagnose the allocator fault and fix it **in source**, so the release build
runs the whole bench cleanly.

## Layout

- `/app/forge.c` — the pool allocator (the **only editable file**). It
  implements a first-fit, singly-linked free-list allocator over one static
  8 MiB arena:
  - `void *forge_alloc(size_t n)` — returns a pointer to at least `n`
    writable bytes, or `NULL` only if no free block is big enough. Allocation
    rounds sizes to 16 bytes and **splits** a free block when the remainder is
    large enough to be useful.
  - `void forge_free(void *p)` — returns a block to the free list.
- `/app/main.c` — the protected bench driver. **PROTECTED**: byte-identical
  checked at verification time. Do not modify, rename, or delete it.
- `/app/Makefile` — the release build (`gcc -O2`). **PROTECTED** the same way.
- `/app/workload.txt` — the visible bench workload (read-only fixture).
- `/app/forgebench` — the release binary; rebuilt from source by `make`.

The driver reads a workload and drives the allocator:

```
A <id> <n>   allocate n bytes, bind to <id> (an already-live <id> is
             released first)
W <id> <v>   fill every byte of live block <id> with byte v (0..255) and
             record v as its fill value
F <id>       release the live block <id>
```

Unknown opcodes, malformed lines and blank lines are ignored harmlessly. At
the end the driver prints exactly one line:

```
FORGE-OK <checksum>
```

where `<checksum>` is the sum, over all **live** blocks, of
`(recorded byte size) * (fill value + 1)` modulo 2^64 (a block never written
has fill value 0).

## The fault

`main.c` honours the allocator contract and writes into every returned block
unconditionally; every hidden workload only ever makes requests that a correct
8 MiB pool can serve (live bytes never exceed the arena). The crash is
therefore entirely inside the allocator's own bookkeeping in `forge.c`: after
a free-then-reallocate sequence, allocation runs off the rails and
`forgebench` dies with SIGSEGV. A local repro is easy: `make -C /app &&
/app/forgebench /app/workload.txt`. `gdb` / `objdump` on the release binary
are your friends.

## What you must do

1. Diagnose the root cause in `/app/forge.c`.
2. Fix it **only in `/app/forge.c`**. Do not weaken the contract (a fix that
   refuses satisfiable requests, or that grows the arena, is not a fix).
3. Rebuild the release binary: `make -C /app clean && make -C /app`.
4. Leave `/app/forgebench` rebuilt from the fixed source, exiting `0` with the
   exact `FORGE-OK <u64>` line on `/app/workload.txt` and on any other valid
   workload.

The verifier **rebuilds from your source** (`make clean && make`) and runs the
fresh binary on the visible workload and on hidden workloads, comparing the
printed checksum against an independent reference simulation of the driver
semantics. It also checks that `main.c` and `Makefile` are still
byte-identical. A wrong fix keeps the crash (or changes the checksum) and
fails; touching a protected file fails immediately.

## Constraints

- gcc, make, gdb, binutils and python3 are installed; no network at verify
  time.
- Do not read `/tests` (it is not present during your work anyway).
- Deliverables: `/app/forge.c` (fixed) and `/app/forgebench` (rebuilt).
