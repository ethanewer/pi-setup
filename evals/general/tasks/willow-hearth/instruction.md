# Breach recovery: decrypt, unseal, bundle

You are a forensic analyst on an isolated Linux box (Ubuntu 24.04 with `gcc`,
`python3`, the `openssl` CLI, and `unzip`/Python `zipfile`; **no network**). A
compromised workstation image was exported into `/app`. You must recover the
subkey of a small round block cipher (`vigil`), decrypt an encrypted payload,
crack the password of an encrypted archive, produce a combined key-and-
certificate PEM, and record the recovered credentials.

## Provided inputs (read-only — do **not** modify them)

- `/app/artifacts/pairs.txt` — known **plaintext/ciphertext** pairs for the
  `vigil` cipher. One pair per line, two lowercase hex tokens separated by a
  space: `PPPP CCCC`. `PPPP` is a 16-bit plaintext block; `CCCC` is its
  ciphertext under the (unknown) subkey. Blank lines and lines starting with `#`
  may occur.
- `/app/artifacts/target.hex` — the encrypted payload: space- or comma-separated
  4-digit lowercase hex tokens, each a 16-bit `vigil` ciphertext block produced
  from consecutive 16-bit ASCII chunks of a credential record.
- `/app/artifacts/dict.txt` — a small candidate passphrase wordlist (one word
  per line).
- `/app/artifacts/secrets.zip` — an encrypted ZIP archive whose single member is
  `secret.txt`. Its password is directly one of the words in `dict.txt`.

## The `vigil` block cipher (full specification)

- **Block size 16 bits.** A **single 16-bit subkey `k`** is XORed in before
  every round's nonlinear step (so the subkey itself is the master key material
  — a compact 16-bit "seed").
- The ciphertext is produced by **`R = 4` rounds**.
  - Rounds 1, 2, 3 (all but the last):
    ```
    st ^= k
    st = Sbox(st)      # substitute each 4-bit nibble
    st = P(st)         # bit permutation
    ```
  - Round 4 (the last round): `st ^= k; st = Sbox(st)` — **no permutation**.
- **S-box** (input nibble index 0..15 -> box nibble), decimal values:
  `14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7`
- **Bit permutation `P`:** bit `i` of the block maps to output bit `P[i]`, with
  `P = {0, 8, 1, 9, 2, 10, 3, 11, 4, 12, 5, 13, 6, 14, 7, 15}` (bit 0 is the
  least-significant bit).
- **Payload layout:** begin big-endian. Each 16-bit block encodes two
  consecutive ASCII bytes as `(byte0 << 8) | byte1`.

### How to recover the subkey

You derive the 16-bit subkey from the known plaintext/ciphertext pairs. Since the
whole key is a compact 16-bit seed, the candidate search space stays small;
implement a genuine linear cryptanalysis flavor — rank candidate keys by a
**linear-bias correlation statistic** (e.g. how far from 0.5 the empirical
correlation of the pair parities sits) — and then confirm the exact key by
re-encrypting the pairs. Then decrypt every block in `target.hex` with that key.

## Deliverables in `/app`

### 1) `/app/decode.c` — the recovery program (a C source you author)

Implement the cipher's encryption **and** decryption, recover the subkey, and
decrypt the supplied ciphertext. Two required entry points:

- **Calling convention** (the test driver depends on it) — return the recovered
  subkey as an **unsigned 32-bit value**:
  ```c
  uint32_t recover_round_key(const char *pairs_path);
  ```
  It reads the pairs from `pairs_path` and returns the recovered 16-bit subkey
  as a `uint32_t` (so a signed or narrower-than-32-bit return is wrong).

- **CLI**:
  ```
  ./decode <pairs.txt> <target.hex>
  ```
  prints exactly two lines to stdout (lowercase hex):
  - `key=<decimal>:subkey as an unsigned base-10 integer>`
  - `plain=<lowercase hex>` — the decrypted 16-bit blocks of `target.hex`
    concatenated in order, each as 4 lowercase hex digits.

Your program must work on inputs you have never seen (fresh pairs and a fresh
target under a different subkey). Compile with `gcc -O2 -o decode decode.c`.

### 2) `/app/key.pem` — combined key + certificate PEM

Use the `openssl` CLI to generate a fresh RSA-2048 private key and a matching
self-signed X.509 certificate (any subject), then write **both PEM blocks into
the single file** `/app/key.pem`: the private-key block first, then the
certificate block, standard PEM headers, file mode `0600`. The certificate's
public key must equal the private key's public key.

### 3) `/app/creds.txt` — the recovered-credentials result file

Exactly these **three lines** (in order):
```
subkey=<decimal value of the recovered subkey as an integer>
passphrase=<the word that unlocks the archive>
record=<the ASCII record recovered from target.hex>
```
The intent: you must *actually run* the recovery in this environment — recover
the subkey with your program, crack the archive password by trying every word of
`dict.txt` against the zip, decrypt `target.hex`, and write the real values.

## Edge cases the verifier probes with fresh hidden inputs

- `pairs.txt` with **2 to 6** pairs; hex may be upper- or lower-case; leading
  whitespace, blank lines and `#` comment lines allowed.
- Any number of blocks in `target.hex` (1, 2, or more).
- The subkey may be any 16-bit value, including `0x0000` and `0xffff` (printed
  as `0` and `65535`).
- `recover_round_key` must never crash and must return `0` on an unreadable or
  malformed pairs file.

## Rules

- Work only inside `/app`. Do not modify the provided artifacts.
- No network access.
- `decode.c` builds cleanly with `gcc -O2`; `key.pem` and `creds.txt` must have
  exactly the documented format.
- Recover every value by running your code — do not guess expected answers.