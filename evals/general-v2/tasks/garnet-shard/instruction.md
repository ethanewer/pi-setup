# garnet-shard — subkey recovery from a breached rotation appliance

You are a forensic analyst on an isolated Linux box (Ubuntu 24.04 with
`gcc`, `python3`; **no network**). A compromised key-rotation appliance
exported its artifacts into `/app`. You must recover the subkey of the
appliance's small block cipher (`gull`) from known plaintext/ciphertext
pairs, decrypt an exfiltrated payload, and expose the recovered subkey
through the exact calling convention the incident driver depends on.

## Provided inputs (read-only — do **not** modify them)

- `/app/artifacts/pairs.txt` — known **plaintext/ciphertext** pairs for the
  `gull` cipher. One pair per line: two hex tokens (1–4 hex digits, case
  insensitive) separated by whitespace: `PPPP CCCC`. `PPPP` is a 16-bit
  plaintext block; `CCCC` is its ciphertext under the (unknown) 16-bit
  subkey. Blank lines and lines starting with `#` may occur.
- `/app/artifacts/target.hex` — the exfiltrated payload: whitespace- or
  comma-separated hex tokens (1–4 hex digits, case insensitive), each a
  16-bit `gull` ciphertext block produced from consecutive 16-bit chunks
  of an ASCII record.

## The `gull` block cipher (full specification)

- **Block size 16 bits**, split into two 8-bit halves: `L = block >> 8`
  (high), `R = block & 0xFF` (low).
- **One 16-bit subkey `k`**: `k_lo = k & 0xFF`, `k_hi = (k >> 8) & 0xFF`.
- **Round function** (input byte `r`, returns a byte):
  ```
  t = r XOR k_lo
  u = (t * 0xB7) mod 256
  u = u rotated left by 1 bit (8-bit rotation)
  F = u XOR ((k_hi + r) mod 256)
  ```
- **Encryption: 3 rounds** of a Feistel swap
  ```
  (L, R) -> (R, L XOR F(R))
  ```
  ciphertext = `(L << 8) | R` after the 3rd round.
- **Decryption** inverts the 3 swaps (the round function need not be
  inverted):
  ```
  (L, R) -> (R XOR F(L), L)     repeated 3 times
  ```
  plaintext = `(L << 8) | R` after the 3rd round.
- **Payload layout:** big-endian — each 16-bit block encodes two
  consecutive ASCII bytes as `(byte0 << 8) | byte1`.

### How to recover the subkey

The whole key material is a compact 16-bit value, so enumerate candidate
subkeys, encrypt each known plaintext, and keep the candidate that matches
**every** provided pair (the pairs uniquely determine one subkey). Then
decrypt every block in `target.hex` with that subkey.

## Deliverables in `/app`

### 1) `/app/gullbreak.c` — the recovery program (C source you author), built as `/app/gullbreak`

Implement the cipher's encryption and decryption, recover the subkey, and
decrypt the supplied payload. One required entry point — the incident
driver links against it and depends on this exact convention:

- **Calling convention** — return the recovered subkey as an **unsigned
  32-bit value**:
  ```c
  uint32_t recover_gull_key(const char *pairs_path);
  ```
  It reads the pairs from `pairs_path` and returns the recovered 16-bit
  subkey as a `uint32_t` in `0..65535` (a signed return, a narrower width,
  or a sign-extended/wrapped value is wrong). On an unreadable, missing, or
  malformed pairs file it must return `0` — and it must **never crash**
  whatever the file contains. Valid pair files always determine a
  **nonzero** subkey.

- **CLI**:
  ```
  ./gullbreak <pairs.txt> <target.hex>
  ```
  prints exactly two lines to stdout:
  - `key=<the subkey as an unsigned base-10 integer>`
  - `plain=<the decrypted 16-bit blocks concatenated in order, each as 4
    lowercase hex digits>`

Build with `gcc -O2 -o gullbreak gullbreak.c`.

### 2) `/app/gullbreak` — the compiled binary

### 3) `/app/creds.txt` — the recovered-credentials result file

Exactly these **two lines** (values from running your program on the
provided artifacts):
```
key=<decimal value of the recovered subkey as an unsigned integer>
plain=<lowercase hex, same content as your program's plain= line>
```

## Edge cases the verifier probes with fresh hidden inputs

- Pair files with **2 to 6** pairs; hex may be upper- or lower-case;
  leading whitespace, blank lines and `#` comment lines may occur.
- Any number of blocks in `target.hex` (1, 2, or more).
- The subkey may be any 16-bit value; a malformed/garbage pairs file must
  yield `0` from `recover_gull_key` (not a crash, not garbage).
- Your program must work on inputs you have never seen, under a different
  subkey.

## Rules

- Work only inside `/app`. Do not modify the provided artifacts.
- No network access. `gullbreak.c` builds cleanly with `gcc -O2`.
- Recover every value by actually running your code — do not guess.
