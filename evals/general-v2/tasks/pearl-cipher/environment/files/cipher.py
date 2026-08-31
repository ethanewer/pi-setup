"""Pearl-Cipher "Pearl32" — reference implementation of the 30-bit block cipher.

This is the AUTHORITATIVE definition of the cipher used by this task. The
verifier checks that this file is unmodified.

Pearl32 is a 4-round Feistel permutation over 30-bit blocks:

  - A block x is an integer 0 <= x < 2^30.
  - Split x into halves  L = (x >> 15) & 0x7FFF   (high 15 bits)
                         R = x & 0x7FFF           (low 15 bits)
  - For round i in 1..4 (in order), with 32-bit round key k = round_key(K, i):
        t = (R + k) mod 2^32
        t ^= t >> 9
        t = (t * 0x045D9F3B) mod 2^32
        t ^= t >> 11
        f = t & 0x7FFF
        (L, R) = (R, L ^ f)
  - Ciphertext y = (L << 15) | R   (again a 30-bit block).

The round schedule derives four 32-bit subkeys from the 32-bit key K:

  def round_key(K, i):
      z = (K ^ (0x9E3779B9 * i)) & 0xFFFFFFFF
      z ^= z >> 16
      z = (z * 0x85EBCA6B) & 0xFFFFFFFF
      z ^= z >> 13
      z = (z * 0xC2B2AE35) & 0xFFFFFFFF
      z ^= z >> 16
      return z

Because every round is invertible, Pearl32 is a bijection on [0, 2^30): for
any key K and any target y in that range there is EXACTLY ONE preimage x.
"""

M32 = 0xFFFFFFFF


def round_key(K, i):
    z = (K ^ (0x9E3779B9 * i)) & M32
    z ^= z >> 16
    z = (z * 0x85EBCA6B) & M32
    z ^= z >> 13
    z = (z * 0xC2B2AE35) & M32
    z ^= z >> 16
    return z


def encrypt(x, K):
    L = (x >> 15) & 0x7FFF
    R = x & 0x7FFF
    for i in (1, 2, 3, 4):
        k = round_key(K, i)
        t = (R + k) & M32
        t ^= t >> 9
        t = (t * 0x045D9F3B) & M32
        t ^= t >> 11
        f = t & 0x7FFF
        L, R = R, L ^ f
    return (L << 15) | R


if __name__ == "__main__":
    import sys
    if len(sys.argv) == 3:
        print("%08x" % encrypt(int(sys.argv[1], 16), int(sys.argv[2], 16)))
    else:
        print("usage: cipher.py <block_hex> <key_hex>", file=sys.stderr)
