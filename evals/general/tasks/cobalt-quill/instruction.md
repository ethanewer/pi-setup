# cobalt-quill — recover the bootloader's orca signing key

A hardware vendor's bootloader verifies firmware with a tiny 32-bit block
cipher called **orca**. A defective batch leaked known plaintext/ciphertext
pairs and one encrypted credential payload. You must write the recovery
program in C, recover the embedded 32-bit key, decrypt the payload, and record
the results — the build farm then re-runs your recovery function through a
fixed **calling convention** on fresh hidden fixtures.

## Environment

Ubuntu-style image with `gcc`, `python3`; **no network**. The leaked artifacts
are in `/app/artifacts/` (read-only — do **not** modify them):

- `pairs.txt` — known plaintext/ciphertext pairs, one per line: two 32-bit hex
  tokens `PPPPPPPP CCCCCCCC`. Parsing tolerance you must support: blank lines;
  lines starting with `#` (after optional whitespace); leading whitespace;
  hex digits in upper or lower case; an optional `0x`/`0X` prefix on a token;
  the two tokens may be separated by whitespace and/or commas.
- `target.hex` — the encrypted payload: whitespace-separated 32-bit hex tokens
  (same case/prefix tolerance), each an orca ciphertext block.

## The orca cipher (full specification)

- 32-bit block, one 32-bit key `K`, all arithmetic on `uint32_t` mod 2^32.
- Encryption: `C = mix(P ^ K)` where `^` is bitwise XOR.
- `mix(x)` (in order):
  1. `x ^= x >> 15`
  2. `x *= 0x2545F491u` (unsigned 32-bit multiply; the constant is odd, hence
     invertible mod 2^32)
  3. `x ^= x << 7` (discard anything above bit 31)
- `unmix(y)`, the exact inverse (documented so you can implement it directly):
  1. undo step 3: `x = y ^ (y << 7) ^ (y << 14) ^ (y << 21) ^ (y << 28)` (each
     shift followed by masking to 32 bits)
  2. undo step 2: `x *= 0x41444C71u` (this is the modular inverse of
     `0x2545F491` mod 2^32)
  3. undo step 1: `x ^= x >> 15; x ^= x >> 30`
- Decryption: `P = unmix(C) ^ K`.

### How to recover the key

From any single pair, `K = unmix(C) ^ P`. The full key space is 2^32, so the
analytic route above is the intended one; a brute-force search is not
acceptable. You must confirm the candidate against **every** parsed pair.

## Deliverables in `/app`

### 1) `/app/keyfind.c` — the recovery program (C source you author)

- **Required calling convention** (the build farm's driver depends on it):

  ```c
  #include <stdint.h>
  uint32_t recover_key(const char *pairs_path);
  ```

  It parses the pairs file at `pairs_path` and returns the recovered 32-bit key
  as an **unsigned 32-bit value** (a signed return, a narrower width, or a
  sign-extending conversion is wrong: hidden keys include values like
  `0xDEADBEEF` and `0xFFFFFFFF`). It must:
  - return `0` if the file cannot be opened, contains no valid pair, or the
    parsed pairs are mutually inconsistent (no single key explains them all);
  - never crash on any input (truncated tokens, empty file, garbage bytes).

- **CLI** (build with `gcc -O2 -o keyfind keyfind.c`):

  ```
  ./keyfind <pairs.txt> <target.hex>
  ```

  prints exactly two lines to stdout:
  - `key=<decimal>` — the recovered key as an unsigned base-10 integer
    (e.g. key `0xFFFFFFFF` must print as `4294967295`, never a negative number);
  - `plain=<lowercase hex>` — each block of `target.hex` decrypted with the
    recovered key as `P = unmix(C) ^ K`, concatenated in order, each block as
    exactly 8 lowercase hex digits.

### 2) `/app/creds.txt` — the recovered-credentials record

Exactly two lines:

```
subkey=<decimal value of the key recovered from /app/artifacts/pairs.txt>
record=<the ASCII payload from /app/artifacts/target.hex>
```

The payload blocks encode consecutive 4-byte big-endian ASCII chunks (any
trailing pad is spaces, `0x20` — trim nothing, but spaces at the end may be
omitted in `record=`). Recover every value by actually running your program —
do not guess.

## What the build farm (verifier) checks

- It compiles `/app/keyfind.c` both as a shared object (to call
  `recover_key` through the documented `uint32_t` convention via its driver)
  and as the CLI binary. A failed compile fails everything.
- It runs `recover_key` on **hidden** pairs files under different keys —
  including keys with the top bit set — and compares the returned unsigned
  32-bit value exactly.
- It runs the CLI on hidden pairs/target fixtures (1 to 7 blocks) and compares
  `key=` and `plain=` byte-for-byte.
- One hidden pairs file is deliberately malformed; `recover_key` must return
  `0` there.
- It checks `/app/creds.txt` against the visible artifacts.

## Rules

- Work only inside `/app`; do not modify `/app/artifacts/*`.
- No network access. Standard C library only.
- Deterministic output; the CLI must not print anything except the two lines.
