# wren-link — Skerry plugin SDK: coalesce per-module LLVM IR

You are the build engineer for the **Skerry** audio-plugin SDK. The DSP stack
was refactored into separate per-module LLVM IR files, and the release build is
broken: nothing links the loose modules back together. Your job is to restore a
working end-to-end IR build. Work under `/app`; **do not modify** anything in
`/app/src/` (the shipped sources are locked).

## Provided inputs (read-only)

- `/app/src/gain.ll` — defines `sk_gain(i32)` and `sk_mix(i32,i32)`.
- `/app/src/envelope.ll` — *declares* `sk_gain` (a genuine cross-module
  reference) and defines `sk_shape(i32)` which calls it.
- `/app/src/limiter.ll` — declares `sk_gain` and `sk_shape`, defines
  `sk_limit(i32)` which calls both.
- `/app/src/main.c` — the demo harness with `main()` that calls all four
  functions and prints four `name=value` lines. Do not modify it.

The LLVM/clang toolchain (LLVM 18: `clang-18`, `llvm-link-18`, `llvm-nm-18`,
`llvm-dis-18`, …) is installed.

## Deliverables (all three required)

### 1. `/app/link.sh` — generic IR coalescer

An executable shell script with the interface:

```
/app/link.sh OUT.bc IN1.ll [IN2.ll ...]
```

It must drive the system `llvm-link` (try `llvm-link-18`, then other
`llvm-link-*` versions, then plain `llvm-link`) over **any** number of input
`.ll` modules and write the single combined bitcode module to `OUT.bc`. It must
work for arbitrary module sets — not just the shipped fixtures — and exit
non-zero on failure. Do not hard-code input names inside the script.

### 2. `/app/plugin.bc` — the combined plugin module

Produce it with your own tool from the shipped modules:

```
/app/link.sh /app/plugin.bc /app/src/gain.ll /app/src/envelope.ll /app/src/limiter.ll
```

`/app/plugin.bc` must be a **single linkable bitcode module** in which every
cross-module reference is resolved:

- it defines `sk_gain`, `sk_mix`, `sk_shape`, and `sk_limit`;
- `llvm-nm-18 --defined-only /app/plugin.bc` lists all four;
- `llvm-nm-18 --undefined-only /app/plugin.bc` lists **none** of those four
  (no leftover `declare` for them). Undefined symbols for runtime/library
  functions are irrelevant here (these modules have none).

### 3. `/app/skerry_demo` — the rebuilt native demo

Compile the harness and link it against the combined module:

```
clang-18 -c -emit-llvm /app/src/main.c -o /tmp/main.bc
clang-18 -O1 /tmp/main.bc /app/plugin.bc -o /app/skerry_demo
```

(Any equivalent native build of the same two bitcode inputs is acceptable, as
long as `/app/skerry_demo` is a runnable x86-64 ELF.)

Running it must print exactly:

```
gain=12
mix=21
shape=34
limit=36
```

(gain: 5+7; mix: (3+7)+(4+7)=21; shape: (10+7)*2; limit: (29+7)*2-(29+7)) — do not
hand-write these lines; the verifier re-runs your binary.

## How the verifier grades

1. It **re-runs `/app/link.sh`** on two *hidden* module sets (different
   functions, different cross-module call chains, different main harnesses),
   links the result with that set's harness, runs the binary, and checks the
   printed output. So `link.sh` must be fully generic.
2. It checks `/app/plugin.bc` with `llvm-nm-18`: all four Skerry functions
   defined, none of them undefined (the classic failure modes here are
   **undefined symbols** from forgetting a module and **duplicate symbols**
   from linking a module twice — both fail).
3. It executes `/app/skerry_demo` and compares its stdout to the expected
   output above.

If any link/build step is wrong, the resulting executable fails to build or
prints wrong values — there is no way to satisfy the checks without a real
coalescing link.

## Constraints

- No network at run or verify time. Use only the preinstalled LLVM/clang.
- `link.sh` must not hard-code `/app/src/*` paths; it consumes only its
  command-line arguments.
- Keep the shipped `.ll`/`.c` fixtures unmodified.
