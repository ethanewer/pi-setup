# calm-hearth

Three independent low-level debugging tasks, all in `/app`. Deliverables must be
left at the exact paths below. Work only in `/app`; use the installed
toolchain (gcc/g++, make, gdb, clang, binutils/objdump, valgrind, python3).

Leave these files as they are unless explicitly told otherwise. Note well:

- **`/app/main.cpp` and `/app/Makefile` are PROTECTED.** Their contents are
  checked (byte-identical) at verification time. Do **not** modify, rename, or
  delete them.
- **`/app/user.cpp` is the ONLY editable heap source.** The fix must be made
  here, in the source, not via environment variables or runtime wrappers.
- **`/app/libtransform.so` and `/app/target/render` are fixtures.** Do not
  modify or replace them.
- Do not read `/tests` (it is not present during your work anyway).

---

## Task 1 — fix the release-mode custom-heap crash

`/app/user.cpp` implements a small custom memory heap: a boundary-tag, first-fit,
singly-linked **free-list allocator** over one static arena. The arena is
`1 << 24` bytes (16 MiB), defined by `ARENA_SIZE` in `user.cpp`. It exposes:

```cpp
extern "C" void *heap_alloc(size_t size);   // NULL only if nothing big enough is free
extern "C" void  heap_free(void *p);        // returns a block to the free list
```

The protected driver `/app/main.cpp` reads a **workload** and drives the heap:

```
fixedheap <workload-file>
```

Workload grammar (space-separated tokens, one command per line):
- `A <n>` — allocate a block of `n` bytes; remember it.
- `W <v>` — write the value `v` (0..255) into **every byte** of the **most
  recently allocated** live block.
- `F`      — free the **most recently allocated** live block.
- anything else (unknown opcodes, blank lines, `A`/`W` with a non-numeric
  argument) is **ignored harmlessly** (including `A 0`, which becomes an 8-byte
  allocation but contributes `0` to the checksum because its recorded size is 0).

`fixedheap` prints exactly one line to stdout:

```
HEAP-OK <checksum>
```

where `<checksum>` is the sum, over **all currently-live** blocks, of
`(recorded byte size) * (fill value)`, as an unsigned 64-bit integer.

**The bug:** in a `-O2` release build the shipped heap crashes. `main.cpp`
assumes that any request a correct 16 MiB arena can satisfy always returns a
pointer — it writes unconditionally into the returned pointer, so a heap that
fails to honour that contract segfaults. Every hidden workload only ever makes
requests that a correct arena serves (concurrent live bytes never exceed the
arena), so the fault is entirely inside the **heap's own bookkeeping**: freed
blocks are never handed out again, and after a free-then-reallocate sequence
`heap_alloc` runs out of space and returns `NULL`. Fix the memory/heap handling
in `user.cpp` so released blocks are reclaimed and every in-bounds request
succeeds.

You must:
1. Diagnose the fault (it is isolated to `user.cpp`; `gdb`, `objdump`, and a
   local repro workload are your friends).
2. Apply the fix **only in `/app/user.cpp`**.
3. Rebuild the release binary: `make -C /app clean && make -C /app`
   (this produces `/app/fixedheap` from the *fixed* `user.cpp` + the protected
   `main.cpp` and `Makefile`).
4. Leave `/app/fixedheap` executable and working; it must finish with exit `0`,
   no crash, the exact `HEAP-OK <u64>` line above, and a clean leak profile
   under valgrind.

## Task 2 — call the native library with the correct FFI signature

`/app/libtransform.so` exports one symbol:

```c
long long scramble_hill(unsigned char *buf, unsigned long n);
```

It transforms the buffer **in place** and returns a 64-bit signed integer.
Write `/app/callffi.py` that:

- Takes two arguments: `python3 /app/callffi.py <input> <output>`.
- Loads `/app/libtransform.so` with `ctypes`.
- Calls `scramble_hill` passing a **pointer to the buffer** (a mutable writable
  buffer holding the input file's bytes) and the byte count, with the **return
  type typed as a 64-bit signed integer** so the integral result reads back
  correctly.
- Writes the (now-transformed) buffer bytes to `<output>`.
- Prints exactly one line to stdout: `FFI-RET <signed_int64>`.

Edge cases the hidden cases probe: the empty input file (0 bytes), single
bytes, and arbitrary non-text byte buffers. The verification independently
recomputes the expected return value and the exact transformed bytes from the
input. Get the pointer/arity/return type exactly right — a mismatched signature
silently reads garbage and fails.

## Task 3 — reverse-engineer the native target

`/app/target/render` is a compiled C binary you did not receive the source for.
Read a **grid file** and print a result to **stdout**:

```
render <grid-file>
```

Grid file format: the first line is `H W` (height, width). The next `H` lines
each contain `W` integers in the range `0..255`.

Your job: determine **which rendering/scene operation** the binary performs —
by running it on probe grids, by disassembling it with `objdump`, by inspecting
it under `gdb`, or any combination — and write `/app/reimpl.py` that reproduces
it exactly:

- `python3 /app/reimpl.py <grid-file>` must print the **identical bytes** to
  stdout that `/app/target/render <grid-file>` prints, for any valid grid
  (including `1x1`, different sizes, and values at the extremes of `0..255`).
- Document your findings (the operation, its kernel/weights, any rounding or
  edge-handling rule, and the exact output format) in **`/app/notes.md`**.

The verifier compares `reimpl.py`'s stdout against the native binary's stdout
byte-for-byte on hidden grids. A reimplementation that captures only part of the
transformation, or that slips on corner/edge rounding, will differ and fail.

---

## Definition of done

All four deliverables exist and pass:

- `/app/fixedheap` — rebuilt from the fixed `user.cpp`; exits `0`, prints the
  correct checksum, handles the documented edge cases, and is valgrind-clean.
- `/app/callffi.py` — correct-typed FFI call; `FFI-RET <int64>` on stdout and
  the transformed `<output>` bytes match reference for every hidden input.
- `/app/reimpl.py` — stdout byte-identical to the native `render` on hidden
  grids.
- `/app/notes.md` — documents the heap root cause and the reverse-engineered
  rendering operation.

Protected files (`main.cpp`, `Makefile`) stay byte-identical; fixtures stay
untouched. All paths are absolute as given above.
