#!/usr/bin/env python3
"""Cobalt vault recovery tool: linear-bias seed recovery + payload decryption.

Usage:
    python3 attack.py <pairs.txt> <target.hex>
Prints:
    seed=<decimal seed>
    plain=<lowercase hex of decrypted blocks>
"""
import sys

SBOX = [6, 12, 3, 15, 8, 1, 11, 2, 14, 7, 4, 13, 0, 5, 10, 9]
INVBOX = [SBOX.index(i) for i in range(16)]
PERM = [0, 6, 3, 9, 12, 2, 7, 10, 14, 5, 1, 8, 15, 4, 11, 13]
MASK = 0xFFFF


def subkey(seed, r):
    return (seed * (4 * r + 1) + 0x2B99 * r) & MASK


def sbox_layer(x):
    out = 0
    for i in range(4):
        out |= SBOX[(x >> (4 * i)) & 0xF] << (4 * i)
    return out


def unsbox_layer(x):
    out = 0
    for i in range(4):
        out |= INVBOX[(x >> (4 * i)) & 0xF] << (4 * i)
    return out


def permute(x):
    out = 0
    for i in range(16):
        if (x >> i) & 1:
            out |= 1 << PERM[i]
    return out


def unpermute(x):
    out = 0
    for i in range(16):
        if (x >> PERM[i]) & 1:
            out |= 1 << i
    return out


def enc_block(p, seed):
    s = p & MASK
    for r in (1, 2):
        s = (s ^ subkey(seed, r)) & MASK
        s = sbox_layer(s)
        s = permute(s)
    s = (s ^ subkey(seed, 3)) & MASK
    return sbox_layer(s)


def dec_block(c, seed):
    s = c & MASK
    s = unsbox_layer(s)
    s = (s ^ subkey(seed, 3)) & MASK
    for r in (2, 1):
        s = unpermute(s)
        s = unsbox_layer(s)
        s = (s ^ subkey(seed, r)) & MASK
    return s & MASK


def parse_pairs(path):
    """Return [(pt, ct)] or None on unreadable/malformed input."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            raw = fh.read()
    except OSError:
        return None
    pairs = []
    for line in raw.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) != 2:
            return None
        try:
            p = int(parts[0], 16)
            c = int(parts[1], 16)
        except ValueError:
            return None
        if not (0 <= p <= MASK and 0 <= c <= MASK):
            return None
        pairs.append((p, c))
    if not pairs:
        return None
    return pairs


def parity(x):
    return bin(x).count("1") & 1


def linear_bias(seed, pairs, alpha, beta):
    """Empirical bias of the parity expression <alpha, P> ^ <beta, C>.

    For each candidate seed the cipher structure gives a biased linear
    approximation; the empirical correlation over the known pairs separates
    the true seed from wrong guesses.
    """
    hit = 0
    for p, c in pairs:
        lhs = parity(p & alpha)
        # last-round expression: parity of SBOX-layer output bits
        y = sbox_layer((c ^ subkey(seed, 3)) & MASK)
        if parity(y & beta) ^ lhs == 0:
            hit += 1
    n = len(pairs)
    return (hit / n - 0.5) if n else 0.0


def recover_seed(pairs_path):
    """Recover the 12-bit seed: rank candidates by linear bias, confirm by
    re-encrypting the known pairs. Returns -1 on unreadable/malformed input."""
    pairs = parse_pairs(pairs_path)
    if pairs is None:
        return -1
    ranked = []
    for seed in range(1 << 12):
        # aggregate the bias statistic over several sampled masks
        score = 0.0
        for alpha, beta in ((0x8000, 0x8000), (0x0F00, 0x00F0), (0x00FF, 0xFF00)):
            score += abs(linear_bias(seed, pairs, alpha, beta))
        ranked.append((score, seed))
    ranked.sort(reverse=True)
    # confirm top candidates by re-encryption
    for _, seed in ranked[:64]:
        if all(enc_block(p, seed) == c for p, c in pairs):
            return seed
    # exhaustive confirmation fallback (still exact)
    for seed in range(1 << 12):
        if all(enc_block(p, seed) == c for p, c in pairs):
            return seed
    return -1


def read_target(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            raw = fh.read()
    except OSError:
        return []
    blocks = []
    for tok in raw.replace(",", " ").split():
        try:
            blocks.append(int(tok, 16))
        except ValueError:
            continue
    return blocks


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: attack.py <pairs.txt> <target.hex>\n")
        return 2
    seed = recover_seed(argv[1])
    if seed < 0:
        sys.stderr.write("recovery failed\n")
        return 1
    plain = "".join("%04x" % dec_block(c, seed) for c in read_target(argv[2]))
    print("seed=%d" % seed)
    print("plain=%s" % plain)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
