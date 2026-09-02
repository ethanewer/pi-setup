# Cobalt vault: linear-bias subkey recovery

You are auditing a vault controller that runs a reduced SPN block cipher
("cobalt"). The controller's round subkeys are all derived from a compact
**12-bit seed**, and you have captured known plaintext/ciphertext pairs. Your
job is to write a reusable recovery tool that derives the seed from the pairs
by **linear-bias cryptanalysis**, decrypts the captured payload, and records
the recovered values.

## Provided inputs (`/app/vault/`, read-only — do not modify)

- `spec.py` — the cobalt cipher reference: `SBOX`, `PERM`, the public key
  schedule `subkey(seed, r)`, and `enc_block(p, seed)`. The seed is **not**
  in this file.
- `pairs.txt` — known plaintext/ciphertext pairs, one pair per line: two
  4-digit hex tokens separated by whitespace (`PPPP CCCC`). Lines may be
  blank, carry leading whitespace, or start with `#` (comments) — skip those.
  Hex may be upper- or lower-case.
- `target.hex` — the encrypted payload: space-separated 4-digit lowercase hex
  tokens, each a 16-bit cobalt ciphertext block. Consecutive blocks encode the
  consecutive ASCII characters of a credential record, two characters per
  block, big-endian (`char0 << 8 | char1`).

## The cobalt cipher (full specification)

- **Block size 16 bits.** A 12-bit seed `s` derives three 16-bit round
  subkeys via the public schedule `subkey(s, r) = (s*(4r+1) + 0x2B99*r) mod
  2^16` for `r = 1, 2, 3`.
- Three rounds:
  - Rounds 1 and 2: `st ^= subkey(s, r); st = SboxLayer(st); st = Perm(st);`
  - Round 3 (last): `st ^= subkey(s, 3); st = SboxLayer(st);` — **no
    permutation**.
- `SboxLayer` substitutes each of the four 4-bit nibbles through `SBOX =
  [6,12,3,15,8,1,11,2,14,7,4,13,0,5,10,9]` (nibble 0 is least significant).
- `Perm` maps bit `i` to output bit `PERM[i]` with
  `PERM = [0,6,3,9,12,2,7,10,14,5,1,8,15,4,11,13]` (bit 0 is least
  significant).

## How to recover the seed

Because the entire key material is bounded by a 12-bit seed, the candidate
space is small. Implement a genuine **linear cryptanalysis flavor**: for each
candidate seed, evaluate a linear-approximation parity statistic over the
known pairs — e.g. how far the empirical correlation (bias from 1/2) of a
plaintext-bit/XOR and ciphertext-bit/XOR expression sits from zero — and rank
the candidates by that bias; then **confirm** the top candidates by
re-encrypting the known pairs until the exact seed is identified. Any
method that identifies the true seed is accepted, but the bias-ranking pass
must be part of the tool.

## Deliverables in `/app`

### 1) `/app/attack.py` — the recovery tool

- Must be importable and expose:
  ```python
  def recover_seed(pairs_path: str) -> int
  ```
  It reads the pairs file (tolerating blank lines, leading whitespace, `#`
  comments, and mixed-case hex) and returns the recovered 12-bit seed as an
  `int`. On an unreadable or malformed pairs file it must **return `-1`**
  and never raise or crash.
- Must also work as a CLI:
  ```
  python3 /app/attack.py <pairs.txt> <target.hex>
  ```
  printing exactly two lines to stdout:
  - `seed=<decimal integer>` — the recovered seed in base 10;
  - `plain=<lowercase hex>` — the decrypted 16-bit blocks of `target.hex`
    concatenated in order, each as 4 lowercase hex digits.

### 2) `/app/seed.txt`

Exactly one line: `seed=<decimal integer>` — the seed recovered from the
visible `/app/vault` artifacts (a trailing newline is fine).

### 3) `/app/message.txt`

The ASCII record recovered by decrypting `/app/vault/target.hex` with the
recovered seed: the concatenation of the two characters of every decrypted
block, written as one line.

Produce both files by **running your tool** on the visible artifacts — do not
hand-edit them.

## Edge cases the grader probes with hidden inputs

- 3 to 8 pairs per file; upper- or lower-case hex; blank lines, leading
  whitespace, and `#` comment lines.
- Seeds anywhere in `0..4095`, including `0` and `4095`.
- Payloads of 1 to many blocks, with uppercase letters, digits, hyphens,
  colons, and spaces.
- `recover_seed` on a malformed or missing pairs file returns `-1` (no crash).

## Constraints

- Work only under `/app`. Do not modify `/app/vault` or read `/tests`.
- No network access; Python standard library only.
- The grader re-runs your tool on fresh hidden pairs/targets under different
  seeds, so nothing may be hard-coded to the visible values.
