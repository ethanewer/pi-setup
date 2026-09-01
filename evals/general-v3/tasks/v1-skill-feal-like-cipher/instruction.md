# FEAL-like cipher

Implement a small FEAL-*like* Feistel block cipher operating on 8-byte blocks.

## Primitives

- Byte rotate-left-2: `rot(x) = ((x << 2) | (x >> 6)) & 0xFF`.
- Round box: `F(R, K)[i] = rot((R[i] + K[i]) & 0xFF)` for byte positions `i` in
  0..3, where `R` and `K` are 4-byte lists.
- Byte XOR: `X(a, b) = [a[i] ^ b[i] for i in 0..3]`.

## Fixed round keys (constants, not secret)

```
K0 = [0x12, 0x23, 0x45, 0x67]
K1 = [0x89, 0xAB, 0xCD, 0xEF]
K2 = [0xFE, 0xDC, 0xBA, 0x98]
K3 = [0x76, 0x54, 0x32, 0x10]
```

## Encryption

An 8-byte block is split into left `L = block[0:4]` and right `R = block[4:8]`
(for a fixed round index i from 0 to 3):

```
newL     = R
newR     = xor(L, F(R, K[i]))
L, R     = newL, newR
```

After all 4 rounds the ciphertext (8 bytes) is `L + R`.

## Your task

`/app/plaintext.bin` contains an 8-byte plaintext (its hex is
`0102030405060708`).

Write a Python 3 script `/app/cipher.py` that:

1. reads `/app/plaintext.bin`,
2. implements the cipher exactly as defined above,
3. encrypts the plaintext,
4. writes `/app/cipher.bin` (the 8 raw ciphertext bytes) and writes
   `/app/cipher.json`:
   ```json
   {
     "plaintext": "0102030405060708",
     "ciphertext": "<lowercase hex of the 8 ciphertext bytes>"
   }
   ```

Then run the script so both `/app/cipher.bin` and `/app/cipher.json` exist. The
verifier encrypts the same plaintext independently using the same rules and
checks both outputs.