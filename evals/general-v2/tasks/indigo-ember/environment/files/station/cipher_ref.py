"""Beacon relay cipher reference (16-bit block, 16-bit key).
The key is NOT in this file.
Round: s ^= k; s = rotl16(s, 3); s = (s + 0x7A3B) & 0xFFFF. Four rounds.
"""
MASK = 0xFFFF

def rotl16(x, n):
    return ((x << n) | (x >> (16 - n))) & MASK

def rotr16(x, n):
    return ((x >> n) | (x << (16 - n))) & MASK

def enc_block(p, k):
    s = p & MASK
    for _ in range(4):
        s = (s ^ k) & MASK
        s = rotl16(s, 3)
        s = (s + 0x7A3B) & MASK
    return s & MASK

def dec_block(c, k):
    s = c & MASK
    for _ in range(4):
        s = (s - 0x7A3B) & MASK
        s = rotr16(s, 3)
        s = (s ^ k) & MASK
    return s & MASK
