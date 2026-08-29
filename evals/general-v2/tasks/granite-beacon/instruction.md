# granite-beacon — the alluvial build bench

You are the build engineer for **Meridian-Sounder**, an instrument house that
keeps a row of small command-line tools on a shared benchmark host. Your job is
to take one multi-toolchain build bench (the **granite beacon**) from broken to
a green, measured, headless state. Everything must run on this one container.

You must produce the following **deliverables** at **exact** paths:

| path | what |
|------|------|
| `/app/modernized/` | modernized C++ project that configures+builds and yields a converter executable |
| `/app/legacy_build.log` | log of a successful **headless (non-X11)** build of the legacy tool |
| `/app/compressor/` | a Rust crate whose codec passes `cargo test` and round-trips |
| `/app/compressor_tests.log` | log of a green `cargo test` run of that crate |
| `/app/compcert_bin` | an ELF executable genuinely compiled by the **CompCert** toolchain |
| `/app/sizes.tsv` | a TSV table of the on-disk byte sizes of the real binaries |

There are **five** competencies to satisfy. Each is mandatory; the verifier
re-runs your builds and your programs on hidden inputs. Work only inside
`/app`. Never modify `/tests`.

---

## Part 1 — modernize a legacy C++ converter (`/app/modernized`)

`/app/modernized/` is a CMake project, `choron`, that was written for an early
2000s toolchain. It refuses to build on this container's modern C++17 compiler
because of **obsolete constructs**: a non-standard `<hash>` header include, the
removed `register` storage class, and the removed `std::auto_ptr`. Make it
build and behave exactly as specified.

- Keep the project layout and target name (`add_executable(choron ...)`).
- The configure step must be `cmake -S /app/modernized -B /app/modernized/build`
  followed by `cmake --build /app/modernized/build`. This must succeed on the
  default compiler (g++, C++17). The resulting program is
  `/app/modernized/build/choron`.
- The compiler defaults to C++17 (set `CMAKE_CXX_STANDARD 17`). Remove the
  obsolete constructs so it compiles. Do **not** downgrade the standard.

**`choron` contract.** Reads lines from stdin. For each line that contains a
`=` character: let `key` be everything before the first `=` (leading/trailing
whitespace trimmed), and `value` be everything after it. Compute the **sum of
the decimal digits** of the integer that starts `value`:

- Skip leading whitespace in `value`, then an optional single leading `-`, then
  read the maximal run of decimal digits (`0`–`9`) that follows.
- If there are no such digits, the line produces **no** output (it is skipped).
- Otherwise write one line `key:SUM` (no extra whitespace).

Examples:

```
alto = 7482        ->   alto:21
tempo=0            ->   tempo:0
compass = 1001     ->   compass:2
beacon = -18       ->   beacon:9
solo =             ->   (skipped: value empty)
# pure text        ->   (skipped: no '=')
```

Edge cases the hidden cases probe:
- an **empty input file** must produce **empty output**;
- lines that contain `=` but an empty `value` (e.g. `solo =`) must be skipped;
- lines with the sum `0` (e.g. `nul = 0` or `nul = 00`) must still emit
  `nul:0`;
- whitespace around `=` and around the key must be trimmed.

---

## Part 2 — port a C codec to a Rust crate (`/app/compressor`)

`/app/compressor/` is a half-finished Rust crate named `beaconpack`. The
reference C implementation of the codec is at
`/app/compressor/reference/compressor.c`. The `src/lib.rs` functions
`compress` / `decompress` contain placeholder bodies — **remove** them and
implement the exact byte format below so the crate compiles, `cargo test`
passes (unit/integration tests are already in `tests/port.rs`), and the provided
`--bin probe` binary round-trips bytes.

### Wire format (must be followed byte-for-byte)

Compressed output is: `[0xC5] [length: u32 LE] [run stream...]`

- byte 0 is the fixed magic `0xC5`.
- bytes 1..5 are the **uncompressed** input length as a little-endian `u32`.
- the run stream encodes maximal runs of consecutive equal bytes: for a run of
  `len` equal bytes (1 <= len <= 255) emit one byte `(len - 1)` then the value
  byte. A run longer than 255 bytes is emitted as several 255-byte runs.
- compressed the empty input is exactly 5 bytes: `C5 00 00 00 00`.

`decompress` must:
- return `Err("bad magic")` if the input is shorter than 5 bytes or `code[0]`
  is not `0xC5`;
- return `Err("truncated")` if the run stream ends before the declared length
  is filled;
- return `Err("overshoot")` if a run would take the output past the declared
  length.

Tests in `tests/port.rs` lock these behaviours (including the fixed compressed
bytes for input `zzzz`: `C5 04 00 00 00 03 7A`). You must not delete or weaken
the tests.

You must also:
- run `cargo test` and capture it to `/app/compressor_tests.log` (it must show
  `test result: ok` and `0 failed`);
- make `cargo build --release` succeed so that
  `/app/compressor/target/release/probe` exists.
- The final `src/lib.rs` must contain **no** placeholder markers
  (`todo!`, `unimplemented!`, `panic!`).

The verifier runs `probe` on hidden files; `probe <file>` prints
`{"original_len":N,"compressed_len":M,"roundtrip_ok":BOOL}`. The hidden
high-redundancy inputs must compress (compressed_len < original_len) and
round-trip; the hidden empty input must round-trip.

---

## Part 3 — headless build of a legacy tool (`/app/legacy_build.log`)

`/app/legacy_tool/` is a CMake project `transwc` with a computing *core* and an
optional X11 frontend toggled by `ENABLE_GUI` (default `ON`; it requires the
X11 headers). On this container the X11 development headers are **not**
installed, so an `ON` build cannot link. Build the **headless core only**: the
binary must be produced with the GUI disabled, must run from stdin, and must
**not** link any X11 client library (`libX11`, `libXt`, …).

Produce a successful headless build and record it. Deliverables:
- `/app/legacy_build.log` — a text log whose last meaningful line contains the
  marker `HEADLESS_BUILD_OK` followed by the path of the produced binary.
- the headless binary installed at `/app/legacy_tool/bin/transwc` (so calling
  `transwc` after `/app/legacy_tool/bin` is on PATH works).

`transwc` engine behavior: it reads lines from stdin; for each line containing a
`:` it prints `key:engine(n)` where `key` is the text before the first `:` 
(with surrounding whitespace trimmed) and `n` is the integer after it, and
`engine(n) = n*n` when `n >= 0`, else `0`. Lines without `:` and empty input
produce nothing.

Example: `port:7` => `port:49`; `grid:0` => `grid:0`; `neg:-3` => `neg:0`.

Hidden tests rebuild the project with `-DENABLE_GUI=OFF`, check the produced
ELF via `ldd` links **no** `libX11`/`libXt`, run it against hidden input lines,
and confirm your `/app/legacy_build.log` contains `HEADLESS BUILD_OK`.

---

## Part 4 — produce CompCert-built ELF (`/app/compcert_bin`)

The **CompCert** verified C compiler (the `ccomp` binary, from the Coq toolchain
via opam) is **not** preinstalled; if needed, install it yourself (opam is
available; the official Coq opam repository holds the `coq-compcert` package).
Then compile the provided C source `/app/verifymesh/beacon.c` into a standalone
ELF executable at exactly `/app/compcert_bin`:

- build command is `ccomp /app/verifymesh/beacon.c -o /app/compcert_bin` (or with `-O2`);
- then run `strip /app/compcert_bin` and remove the `.comment` section
  (e.g. `objcopy --remove-section .comment`) so the finished ELF carries **no**
  `GCC:`/`Clang:` `.comment` signature (evidence it wasn't a stand-in mainstream
  compiler);
- `file /app/compcert_bin` must report an x86-64 ELF whose `main` prints
  `BEACON <a> <b> <c>` and exits `0`.

The verifier independently recompiles the **canonical** `beacon.c` (a copy it
keeps hidden) with `ccomp`, extracts the machine-code section, and requires the
hexadecimal hash (e.g. `objcopy --dump-section .text=...` + `md5sum`) to be
**byte-identical** to the same section of `/app/compcert_bin`. That guarantees
the artifact really came from the CompCert toolchain, not a renamed gcc/clang.
It also runs `/app/compcert_bin` and checks stdout and exit code.

Use the exact source you are given as `/app/verifymesh/beacon.c`; do not modify
it (a different source will not match the hidden recompile).

---

## Part 5 — accurate binary-size table (`/app/sizes.tsv`)

Compile `/app/opt/kern.c` with **distinct optimization flags** into real
binaries, then record their exact on-disk sizes.

Produce these four binaries (paths fixed):
- `/app/opt/gcc_O0`  — `gcc -O0 /app/opt/kern.c -o /app/opt/gcc_O0`
- `/app/opt/gcc_O2`  — `gcc -O2 /app/opt/kern.c -o /app/opt/gcc_O2`
- `/app/opt/clang_O2`— `clang -O2 /app/opt/kern.c -o /app/opt/clang_O2`
- `/app/compcert_bin` (the Part 4 artifact)

Write `/app/sizes.tsv` with **one tab-separated record per line** of the form
`PATH<SIZE>` — a literal `/app/...` path, a TAB, then the exact byte count of
that file as reported by `stat -c %s` / `size`. No header line. Example:

```
/app/opt/gcc_O0	15832
/app/opt/gcc_O2	15880
/app/opt/clang_O2	16012
/app/compcert_bin	12288
```

Do **not** hard-code sizes; read them from the filesystem at build time. The
verifier stats each path and requires `sizes.tsv` to match within a tolerance
of `0` bytes (exact). If you compile or strip a binary after writing the table,
regenerate the table so the numbers reflect the binaries that actually exist.

---

## Required build contract

- Only ever modify work inside `/app` while producing deliverables.
- The container is root; do not try systemd, GPUs, or a GUI.
- Install anything you need via apt/opam/cargo, but the finished deliverables are
  the files above and nothing may require a running GUI or a display to verify.
- Every `/app` deliverable must be produced by **actually running** the real
  build/tools (compilers, cargo, cmake/compcert) — you are being evaluated on the
  artifacts and their behavior, not on paperwork.

When you are done, the six deliverables above should all exist under `/app` and
every behavior described above must hold (including under hidden/edge inputs).