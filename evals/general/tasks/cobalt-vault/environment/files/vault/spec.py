"""Cobalt vault cipher reference.
16-bit block; a 12-bit seed derives three 16-bit round subkeys via the
public schedule subkey(seed, r) below. The seed itself is NOT here.
"""
SBOX = [6, 12, 3, 15, 8, 1, 11, 2, 14, 7, 4, 13, 0, 5, 10, 9]
PERM = [0, 6, 3, 9, 12, 2, 7, 10, 14, 5, 1, 8, 15, 4, 11, 13]

def subkey(seed, r):
    return (seed * (4 * r + 1) + 0x2B99 * r) & 0xFFFF

def sbox_layer(x):
    out = 0
    for i in range(4):
        out |= SBOX[(x >> (4*i)) & 0xF] << (4*i)
    return out

def permute(x):
    out = 0
    for i in range(16):
        if (x >> i) & 1:
            out |= 1 << PERM[i]
    return out

def enc_block(p, seed):
    s = p & 0xFFFF
    for r in (1, 2):
        s = (s ^ subkey(seed, r)) & 0xFFFF
        s = sbox_layer(s)
        s = permute(s)
    s = (s ^ subkey(seed, 3)) & 0xFFFF
    return sbox_layer(s)
