# SkyMark "ring" native stack

Build the **SkyMark** C/C++ math stack: a plain-C autoregressive sampler driven
by JSON weights, a C++11-strict portable template port, a CMake project that
emits LLVM IR for every translation unit, a Makefile with serial and parallel
binaries, and a working native↔Python binding. One driver script wires it all
together and writes a JSON answer file.

Everything runs and is verified in one Ubuntu container (`gcc`, `g++`,
`clang`, `cmake`, `make`, libomp and the LLVM tools are installed). Work only
under `/app`.

## What is already present (fixtures — do NOT modify)

```
/app/gen/demo.json          a small JSON weight file for the sampler
/app/sim/part.c             serial ring particle sim source
/app/sim/part_omp.c         OpenMP parallel ring sim source (same physics)
/app/sim/part.h             shared physics constants
/app/cir/src/alpha.c        C translation unit 1
/app/cir/src/beta.c         C translation unit 2
/app/cir/src/gamma.c        C translation unit 3
/app/bind/pad.c             tiny native routine used by a ctypes binding
/app/tpl/legacy.hpp         the C++ header BEFORE your port (breaks C++11)
```

## 2. Deliverables

Exactly these artifacts must exist under `/app`:

1. **`/app/solve.py`** — a Python 3 driver that does real work: compiles/builds
   every component, runs it, and is **re-runnable**: running
   `rm /app/answer.json && python3 /app/solve.py` must reproduce
   `/app/answer.json`. It must exit `0` on success and nonzero on any failure.
2. **`/app/answer.json`** — produced by `/app/solve.py`; valid JSON describing
   what was built and demonstrative results (the sampler token ids for the demo
   prompt, the sim target names, the LLVM IR artifact paths, the C++11 header
   path, the binding path).

You must also create these **authored files** (referenced by `solve.py`):

- `/app/gen/sampler.c` — the C weight-parser + argmax sampler (component 3)
- `/app/sim/Makefile` — with `serial` and `pgen` targets (component 4)
- `/app/cir/CMakeLists.txt` — CMake config emitting LLVM IR per TU (component 5)
- `/app/tpl/series.hpp` — the C++11 port of `/app/tpl/legacy.hpp` (component 6)
- `/app/bind/bad.py` — the ctypes binding caller (component 7)

## 3. Sampler `/app/gen/sampler` (built from `sampler.c`)

Usage:

```
/app/gen/sampler <weights.json> <length> <prompt_token> [more prompt tokens...]
```

- `length` is the number of tokens to **generate** (>= 0). `length = 0` must
  print nothing and exit `0`.
- The prompt tokens are initial token **ids**. At least one prompt token is
  required. Each prompt token must be an integer in `[0, vocab_size)`.
- Output: the generated token ids, one per line, on stdout. Exit `0`.

The weights file is JSON with keys (the model is deliberately integer-only so
results are deterministic and portable):

```
vocab: [V strings]           token names; token id is its index
dim:   D                     embedding dimension
hidden:H                     feed-forward hidden size
window:W                     context window (how many past tokens the model sees)
emb:   V x D ints            embedding table
keymat: D x D ints           single key/query projection
ffw:   H x D ints,  ffb: H ints     feed-forward layer
out:   V x H ints,  ob:  V ints     output logits head
```

**Forward pass (integer arithmetic only — no floats, no softmax):** to pick the
next token given the history (the last `window` tokens) with `last` being the
newest:

```
q[d]     = sum_e emb[last][e] * keymat[e][d]
for each context position p:
    kp[d] = sum_e emb[p][e] * keymat[e][d]
    score = sum_d q[d]*kp[d]
    w_p   = score if score > 0 else 0
ctx[d]   = sum_p w_p * emb[p][d]
a[h]     = max(0, sum_d ffw[h][d]*ctx[d] + ffb[h])
logit[t] = sum_h out[t][h] * a[h] + ob[t]
next_tok = argmax_t logit[t]     (ties -> smallest t)
```

Append `next_tok` to the history and repeat until `length` tokens are
produced.

**Error rules** (the hidden tests probe every one; each must exit nonzero, print
one diagnostic line to stderr, and print nothing to stdout):

- `length < 0`
- a prompt token id outside `[0, vocab_size)`
- malformed / incomplete JSON (missing matrix, wrong number of rows or columns
  i.e. a ragged matrix, a dimension that is <= 0 or wildly large, no matching
  key, syntax error)
- unknown top-level key

**Demo (must match):**

```
/app/gen/sampler /app/gen/demo.json 6 0 0 0
```
must print
```
5
2
4
4
4
4
```

## 4. Makefile at `/app/sim/Makefile` (component 4)

Write a Makefile with **`serial`** and **`pgen`** targets that compile, from the
given sources, two executables `serial` (from `part.c`) and `pgen` (from
`part_omp.c`, built with `-fopenmp`). `make` / `make serial pgen` must produce
both binaries in `/app/sim/`. Both print one line
`init=<u> final=<u> threads=<n> ms=<t>`; `serial` reports `threads=1`, `pgen`
reports the OpenMP thread count it actually uses (honoring `OMP_NUM_THREADS`)
and must be >1 when run with enough threads. Serial and parallel physics are
identical (bit-for-bit checksums). Do not edit `part.c`, `part_omp.c`,
`part.h`.

## 5. CMake at `/app/cir/CMakeLists.txt` (component 5)

Write a CMake config that, for **every** source in `/app/cir/src`, emits LLVM
bitcode (`clang -std=c11 -emit-llvm -c`) into the build tree, and links the
per-TU artifacts into a **single** `/app/cir/build/bc/unified.bc` module
(`llvm-link`). The outputs the verifier checks: `alpha.bc`, `beta.bc`,
`gamma.bc` and `unified.bc`; `unified.bc` must be valid LLVM bitcode exposing
`ring_radius_r`, `beta_quant`, and `gamma_sep`. Build with:

```
cmake -S /app/cir -B /app/cir/build
cmake --build /app/cir/build
```

## 6. C++11 port `/app/tpl/series.hpp` (component 6)

`legacy.hpp` ships a `constexpr` template `mstr::series<N,T>(x)` that only
compiles under C++17. Port it so it compiles cleanly under
**`g++ -std=c++11 -pedantic-errors -Wall -Werror`** **and** stays genuine
`constexpr` computing the **exact same** recurrence, still callable as
`mstr::series<N,T>(x)`:

```
S_0(x) = 0
S_k(x) = x * S_{k-1}(x) + k     for k = 1..N
```

Your `series<N,T>` must be usable in constant expressions (e.g. inside
`static_assert`) and give identical integer results for any integer of `x`,
including negative `x` and `N = 0`. (Hint: C++11 constexpr functions may
contain only a `return`; express the recursion structurally.)

## 7. Binding `/app/bind/bad.py` (component 7)

Build `/app/bind/pad.c` into a shared library and call it from `bad.py` via
`ctypes` with a **correctly sized** output buffer. The C routine
`long bind_pad(buf, cap, n)` fills the first `min(n, cap)` bytes with the byte
pattern `(i*37 + 11) & 0xFF` and zeroes the rest, returning how many bytes it
wrote (never more than `cap`). `bad.py` must print `ok` and exit `0` when the
call succeeds with a buffer *smaller* than `n` (the classic length mismatch).

## 8. solve.py expectations (summary for the verifier)

The verifier deletes `/app/answer.json`, runs `python3 /app/solve.py`, then
independently re-runs/rebuilds the components on hidden inputs. Concretely a
clocking `solve.py` must:

- compile `/app/gen/sampler` successfully,
- `make -C /app/sim serial pgen` and confirm both binaries were made,
- the `cmake` build above and confirm `unified.bc` exists,
- compile `/app/tpl/series.hpp` with the five values described, ensuring
  `series` remains `constexpr`,
- build the shared library and run `bad.py successfully.
- run the demo sampler and record tokens in `answer.json`.

If any of those fail, `solve.py` must exit nonzero (do not write a stale
`answer.json` on failure).

## Rules

- Work only under `/app`. Do not read or write anything outside `/app`.
- Do not modify the fixtures listed in section 1.
- Your `sampler.c`, `Makefile`.. `CMakeLists.txt`, `series.hpp`, `bad.py`, and
  `solve.py` are the components the verifier exercises; they must be complete
  and general (the sampler must work on arbitrary weight files, the C++11
  header on arbitrary `N`/`x`, the sim on different `N/S/seed`).
- The environment is fully offline; do not attempt network access.