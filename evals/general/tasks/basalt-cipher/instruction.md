# Basalt block-cipher build project

You are authoring a small **C build project** from scratch inside `/app`. It is a
block-cipher tool suite. An external grader will (a) rebuild it via a single
`makefile`, (b) run the built `prog` binary **bare** (via `$PATH`) against hidden
inputs, (c) run an untouched self-test, and (d) re-run your release archive
builder and check it is reproducible.

There is no internet and nothing meaningful pre-installed beyond the C toolchain
(`gcc`, `cmake`, `make`, `zstd`, `tar`, `python3`). Write everything under
`/app`; do not touch `/tests` or `/solution`.

## Deliverables (must exist after you finish)

1. **`/app/Makefile`** — the *single* makefile. Running `make` from `/app` must
   configure and build the whole CMake project and place **three** executables
   into `/app/bin/` (creating the directory as needed).
2. **`/app/bin/prog`** — an executable, statically linked, with **zero external
   shared-library dependencies**. It must be invocable **bare** as `prog` from
   any directory via `$PATH` (add a symlink such as
   `/usr/local/bin/prog -> /app/bin/prog`).
3. **`/app/build.sh`** — an *executable* shell script that rebuilds the project
   and packages the source tree into a **reproducible, zstd-compressed GNU tar**
   at `/app/dist/basalt-src.tar.zst`. Two runs with equal inputs must produce
   **byte-identical** archives.

You also create the supporting project files (`CMakeLists.txt`, `src/*.c`, a
`bin/` output tree). The two companions to `prog` are:

- **`/app/bin/selftest`** — an untouched self-test that does real work (see
  below) and returns a success sentinel.
- **`/app/bin/weft`** — a third executable; a tiny utility that prints the
  decoded byte-length of a hex string: `weft HEX` prints one line `weft=<n>`
  where `<n>` is the number of bytes in `HEX` (exit `0`, and `2` if `HEX` is
  malformed hex).

All three must be built **statically** (`-static`) so `ldd` reports no external
shared dependencies.

## The `prog` contract (fixed, positional argument order)

`prog` takes exactly three positional arguments, never flags, and never
reorders/auto-detects them:

```
prog MODE HEXKEY HEXDATA
```

- `MODE` ∈ {`xor`, `skip`}.
- `HEXKEY` and `HEXDATA` are hex strings (both upper- and lower-case accepted).
  An empty string is a zero-length byte sequence.
- The ciphertext is the result of transforming `HEXDATA` with `HEXKEY`, then
  printed as **lowercase hex**, one byte pair each, followed by a single
  trailing `\n`. When the result is empty, print just that newline.

Decode bytes `D[0..n-1]` from `HEXDATA` and `K[0..m-1]` from `HEXKEY`, where
`n = len(HEXDATA)/2`, `m = len(HEXKEY)/2`:

- `xor`: `out[i] = D[i] XOR K[i mod m]` for `i` in `0..n-1`.
- `skip`: `out[i] = (D[i] + K[(i*3) mod m] * ((i mod 8) + 1)) mod 256`
  for `i` in `0..n-1` (all integer arithmetic).

### Exit codes and edge behavior (the grader probes these exactly)

- **0** — success (including when `HEXDATA` is empty: print a lone newline).
- **1** — wrong number of arguments (anything other than exactly three), **or**
  an invalid/unknown `MODE`. Print a short usage line to **stderr**.
- **2** — malformed hex in either `HEXKEY` or `HEXDATA` (odd number of digits,
  or a non-hex character), **or** an empty `HEXKEY`. Print a short error to
  **stderr**.

These cases must be handled without crashing or hanging, for any content. The
grader sends hidden inputs covering: short keys, keys longer than the data,
single-byte inputs, empty `HEXDATA`, empty `HEXKEY`, non-hex characters, odd
hex lengths, too-few and too-many arguments, invalid modes, uppercase hex, and
a large (256-byte) buffer.

### Strict fixed order

`prog` must treat the arguments strictly positionally — the ciphertext depends
on which value is `HEXKEY` and which is `HEXDATA`. Swapping them must change
the output. Do not sort, detect, or normalize argument order.

## `selftest` (untouched self-test entry)

`selftest` must actually perform a genuine check at runtime — it must not fake
success. At minimum it should: encrypt a fixed message, decrypt it back (the
`xor` mode is self-inverse), and verify the round-trip equals the original; it
must also verify a couple of known-answer vectors. If every check passes it must
print `SELFTEST_OK` and exit `0`. On any failure it must print `SELFTEST_FAIL`
and exit non-zero. There is no path that reports success without running the
checks.

## `build.sh` (reproducible zstd gnu tar)

`build.sh` rebuilds (via `make`) and produces `/app/dist/basalt-src.tar.zst`
containing a GNU tar of the project source tree (e.g. under a top-level
`basalt-1.2/` directory holding `CMakeLists.txt`, `Makefile`, `build.sh`, and
`src/`). It must be **reproducible bit-for-bit**: run it, delete `dist/`, run
it again — both archives must be byte-identical. To achieve this, pin the
tar member order and metadata (e.g. GNU tar flags `--sort=name --owner=0
--group=0 --numeric-owner --mtime=@0 --no-acls --no-xattrs`) and use a fixed
`zstd -19` compression. Do not embed timestamps, hostnames, or uid/gid of the
build user in the archive.

## Rules

- `make`/`make all` from `/app` must build all three executables into
  `/app/bin/` from a clean state (the grader deletes `bin/` and rebuilds).
- The binaries must have **zero external shared-library dependencies**
  (statically linked is the intended approach).
- `prog` must be runnable as a bare command `prog ...` anywhere via `$PATH`.
- Do not read, write, or depend on `/tests` or `/solution`.
