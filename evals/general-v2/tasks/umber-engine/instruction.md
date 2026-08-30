# Cross-runtime integer sequence plus a WebAssembly linear-memory reader

You must produce three deliverables under `/app` and make every one of them
correct and runnable. The verifier executes all three on both visible and
hidden inputs, and inspects one of them for forbidden constructs. Nothing under
`/tests` or `solution/` is visible to you; treat `/app/echo.proto` as a
read-only fixture.

## 1. Integer sequence term by argument, in two runtimes (`/app/seq.py` and `/app/seq.rs`)

Define the integer sequence **A** by:

```
A(0) = 1
A(1) = 1
A(2) = 1
A(n) = A(n-2) + A(n-3)   for n >= 3
```

Each program must read a single non-negative integer `n` from the command line
(`argv[1]`) and print, on one line, the bare integer `A(n)` (no extra text, no
decimal point). Valid inputs are `n` in `[0, 100]`.

- `n = 0, 1, 2` all yield `1`.
- `A(3)=2`, `A(10)=12`, `A(40)=55405`, `A(100)=1177482265857` (sanity anchors
  to check your implementations against, not a spec to hardcode).
- For `n` outside `[0,100]`, for a missing/empty argument, or for a
  non-integer argument, print `ERR` to **stderr** and exit with status **2**.
  Valid hidden inputs stay inside the documentable range, but input handling
  for invalid ones is still checked.

### `/app/seq.rs` — the two runtimes must agree

`/app/seq.rs` must be a standalone Rust program that the verifier compiles with

```
rustc -O /app/seq.rs -o /app/seq_rs
```

and then runs as `/app/seq_rs <n>`. Since `n` stays ≤ 100, a plain `u64` is
ample; choose any implementation you like (iteration preferred so nothing
recurses deeply). The verifier will also **statically inspect the source**:

- it must contain **no `unsafe` keyword / unsafe block**,
- **no `extern` declaration** of any foreign function,
- **no foreign-function/ABI bindings** (no `#[no_mangle]`, no `#[repr(C)]`,
  no `std::ffi`). 

Only **safe Rust**. If any of the above tokens appears in `/app/seq.rs`, that
deliverable fails. The result must match `/app/seq.py` exactly for every valid
`n`.

## 2. grpc python toolchain, installed system-wide

The environment provides the grpc client/server runtime (`grpcio`) and the
protocol-buffer code generator (`grpc_tools`). Both must be importable from the
**system** Python that runs `/app/seq.py`:

- `import grpc` succeeds
- `import grpc_tools` succeeds

The verifier additionally drives the code generator itself by compiling
`/app/echo.proto` with `grpc_tools.protoc` into generated `*_pb2.py` /
`*_pb2_grpc.py` modules into an importable directory and importing them. If the
toolchain is not genuinely system-wide those steps fail.

## 3. WebAssembly linear-memory reader (`/app/wasm.c`)

Write a freestanding C file that compiles, unmodified, with the exact command

```
clang --target=wasm32-unknown-unknown -O2 -nostdlib -Wl,--no-entry -Wl,--export-all -o /tmp/wc.wasm /app/wasm.c
```

The module must export (via that command) a memory containing a 256-byte region
`buffer` (indices `0..255`), and the following functions with **exactly** these
names and semantics:

- `void boot(void)` — populate memory so that the byte at `buffer[i]` equals
  `(i * 13 + 7) & 0xFF` for each `i` in `0..255`. (Use a plain loop writing the
  buffer; the host calls `boot()` before probing.)
- `int producer(int seed)` — return an offset in `[0, 239]` computed exactly
  as `((seed * 31 + 7) % 240)`.
- `int consumer(int offset)` — read **exactly 16 bytes** from linear memory
  starting at `offset` (`buffer[offset + 0]` up to `buffer[offset + 15]`) and
  return their integer sum. Every valid offset keeps the window inside
  `0..255` (offsets max `239`).

The verifier, for each probe (visible and hidden), will:

1. call `boot()`,
2. call `producer(seed)` to learn the dynamic offset,
3. call `consumer(offset)` to get the final integer,
4. independently read the 16 bytes from linear memory at that offset from the
   host side (must be exactly 16 bytes),
5. compare those 16 bytes byte-for-byte against the documented formula, and
   compare the host-computed sum of those bytes against `consumer`'s value.

If `producer`'s formula differs, or `consumer` reads the wrong length or the
wrong offset, the byte / integer comparisons will disagree.

Sanity anchor: `producer(7)` is `224` (since `7*31+7 = 224`, and `224 % 240 =
224`).

## Deliverables

All of the following must exist and be byte-valid in `/app` when you finish,
and must be runnable by the verifier (which compiles the Rust and C sources
itself):

- `/app/seq.py`
- `/app/seq.rs`
- `/app/wasm.c`

Do not modify `/app/echo.proto`. Deliver only these three; do not add a
prebuilt binary (the verifier keeps and recompiles the sources and runs them on
hidden inputs, so hardcoded internal answers never help).