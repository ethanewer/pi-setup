# Item-024 (hard) — recover a hidden 32-bit key from a chosen-plaintext oracle

You are a cryptanalyst. A compiled binary `/app/cullet` is the **only** interface to
an unknown keyed 16-bit block cipher. The 32-bit key is compiled into the binary and
never revealed. You may query the binary as often as you want, and you must recover
enough key material to encrypt and decrypt under the cipher yourself.

## The oracle

```
/app/cullet enc <H4>      -> prints ciphertext of the 16-bit plaintext H4 (0..FFFF)
/app/cullet challenge     -> prints the ciphertext of a sealed known plaintext
```

`enc` accepts a 4-hex-digit (16-bit) plaintext and prints the 4-hex-digit
ciphertext. `challenge` prints one ciphertext (whose plaintext is a fixed, sealed
two-character ASCII constant).

## Cipher structure (fully reverse-engineerable)

The 32-bit key `K` is split into four 8-bit subkey lanes:
`e0 = (K>>24)&0xFF`, `e1 = (K>>16)&0xFF`, `e2 = (K>>8)&0xFF`, `e3 = K&0xFF`.

- `S(y) = (y*7 + 3) & 0xFF` (an affine 8-bit S-box; invertible).
- `ROL(x,n)` rotates the 8-bit byte `x` left by `n`.

The two independent lane functions:

- `laneA(in) = S( S( ROL(in,1) ^ e0 ) ^ e1 )`
- `laneB(in) = S( S( ROL(in,2) ^ e2 ) ^ e3 )`

Encryption of the 16-bit plaintext `P` with high byte `H=(P>>8)&0xFF` and low byte
`L=P&0xFF`:

```
a = laneA(H)
b = laneB(L)
ciphertext = 0xFFFF & ((a<<8) | (a ^ b))
```

Notice the **high byte of the ciphertext is exactly `laneA(H)`, independent of `L`**.
That observation lets you map each lane's 8-bit permutation from chosen plaintexts.

## Your deliverable

1. Recover a 32-bit key whose encryption is **functionally identical** to the
   oracle on every plaintext. Write it to `/app/key.txt` as **8 lowercase hex
   digits** (e.g. `1c9e3a57`). You do not need to hit the exact canonical byte
   values — any logically-equivalent key passes — but it must reproduce the
   oracle for *all* inputs.

2. Decrypt the `challenge` output and write the plaintext to `/app/recovered.txt`
   as **4 uppercase hex digits** (e.g. `4f4b`).

## Verification (how your work is judged)

- `/app/key.txt` must parse as hex and represent a key whose encryption matches the
  live oracle on 64 deterministic fresh plaintext queries chosen by the verifier.
- `/app/recovered.txt` must equal the plaintext you actually decrypt from the
  challenge oracle using your recovered key.

## Tips

- Recover `laneA` entirely: query `enc(0xHH00)` for each H in 0..0xFF; the returned
  high byte is `a=laneA(H)`. (With L=0 you directly read the lane value from the
  output high byte.)
- Recover `laneB` by holding H=0: the low byte of `enc(0x00L)` equals
  `a0 ^ laneB(L)`, and you already know `a0=laneA(0)`.
- Once you have the 256-entry table for a lane, invert the `S(S(x^alpha)^beta)`
  chain to solve for the pair of 8-bit subkeys (try all 256 candidate values for
  the outer subkey until the inner inverse is consistent).
- To decrypt the challenge, brute-force all 2^16 plaintexts (or invert the 8-bit
  lane permutations) using your recovered key until one encrypts to the challenge
  ciphertext.

The environment already contains Python 3. Use it; you may implement in C too.