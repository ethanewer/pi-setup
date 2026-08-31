#!/usr/bin/env python3
"""Reference implementation + fixture generator for the garnet-shard 'gull' cipher.

Block: 16 bits, split into 8-bit halves (L = high, R = low).
Key: 16-bit k; k_lo = k & 0xFF, k_hi = (k >> 8) & 0xFF.
Round function F(r) = ((r ^ k_lo) * 0xB7 mod 256) ^ ((k_hi + r) mod 256)
Encrypt: 3 rounds of (L, R) -> (R, L ^ F(R)); ciphertext = (L << 8) | R.
Decrypt: 3 rounds of (L, R) -> (R ^ F(L), L); plaintext = (L << 8) | R.
"""
import json
import os
import random

ROUNDS = 3


def F(r, k):
    k_lo = k & 0xFF
    k_hi = (k >> 8) & 0xFF
    t = r ^ k_lo
    u = (t * 0xB7) & 0xFF
    u = ((u << 1) | (u >> 7)) & 0xFF  # rotate left by 1
    return u ^ ((k_hi + r) & 0xFF)


def encrypt(p, k):
    l, r = (p >> 8) & 0xFF, p & 0xFF
    for _ in range(ROUNDS):
        l, r = r, l ^ F(r, k)
    return (l << 8) | r


def decrypt(c, k):
    l, r = (c >> 8) & 0xFF, c & 0xFF
    for _ in range(ROUNDS):
        l, r = (r ^ F(l, k)) & 0xFF, l
    return (l << 8) | r


def recover(pairs):
    out = []
    for k in range(0x10000):
        if all(encrypt(p, k) == c for p, c in pairs):
            out.append(k)
    return out


def payload_to_blocks(payload: bytes):
    assert len(payload) % 2 == 0
    return [(payload[i] << 8) | payload[i + 1] for i in range(0, len(payload), 2)]


def blocks_to_hex(blocks):
    return "".join("%04x" % b for b in blocks)


def gen_case(rng, key, npairs, payload, comments=False):
    pairs = []
    while len(pairs) < npairs:
        p = rng.randrange(0x10000)
        if any(p == q for q, _ in pairs):
            continue
        pairs.append((p, encrypt(p, key)))
    # grow until the key is uniquely determined by the pair set
    while len(recover(pairs)) != 1:
        p = rng.randrange(0x10000)
        if any(p == q for q, _ in pairs):
            continue
        pairs.append((p, encrypt(p, key)))
        assert len(pairs) <= 20
    cands = recover(pairs)
    assert cands == [key], (key, cands)
    lines = []
    if comments:
        lines.append("# gull known-plaintext pairs (recovered during the breach)")
        lines.append("")
    for p, c in pairs:
        if comments and rng.random() < 0.4:
            lines.append("")
        if comments:
            lines.append("  %04X %04x" % (p, c) if rng.random() < 0.5 else "%04x %04X" % (p, c))
        else:
            lines.append("%04x %04x" % (p, c))
    blocks = payload_to_blocks(payload)
    ct = [encrypt(b, key) for b in blocks]
    # sanity: decrypt roundtrip
    assert [decrypt(c, key) for c in ct] == blocks
    return {
        "key": key,
        "plain_hex": blocks_to_hex(blocks),
        "pairs_txt": "\n".join(lines) + "\n",
        "target_hex": " ".join("%04x" % c for c in ct) + "\n",
    }


def main():
    outdir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    rng = random.Random(0x6A11)

    visible = gen_case(rng, 0x5A17, 4, b"garnet-cycle:QX7741\n")
    vis_dir = os.path.join(outdir, "files", "artifacts")
    os.makedirs(vis_dir, exist_ok=True)
    with open(os.path.join(vis_dir, "pairs.txt"), "w") as fh:
        fh.write(visible["pairs_txt"])
    with open(os.path.join(vis_dir, "target.hex"), "w") as fh:
        fh.write(visible["target_hex"])
    with open(os.path.join(outdir, "tests", "expected.json"), "w") as fh:
        json.dump({"key": visible["key"], "plain_hex": visible["plain_hex"]}, fh, indent=2)
    print("visible key", visible["key"], visible["plain_hex"])

    hidden = [
        ("H1", gen_case(rng, 0x00FF, 2, b"garnet-ok\n")),
        ("H2", gen_case(rng, 0xABCD, 6, b"garnet-ops:cycle-42\n", comments=True)),
        ("H3", gen_case(rng, 0x8001, 3, b"Q7")),
        ("H4", gen_case(rng, 0x0100, 5, b"shard-91823\n")),
    ]
    for name, case in hidden:
        d = os.path.join(outdir, "tests", "hidden", name)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "pairs.txt"), "w") as fh:
            fh.write(case["pairs_txt"])
        with open(os.path.join(d, "target.hex"), "w") as fh:
            fh.write(case["target_hex"])
        with open(os.path.join(d, "expected.json"), "w") as fh:
            json.dump({"key": case["key"], "plain_hex": case["plain_hex"]}, fh, indent=2)
        print(name, case["key"], case["plain_hex"])

    # malformed case: unreadable-ish garbage pairs -> recover function returns 0
    d = os.path.join(outdir, "tests", "hidden", "HM")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "pairs.txt"), "w") as fh:
        fh.write("# nothing but noise\n\nthis is not a pair\nzqqq wxyz\n")
    with open(os.path.join(d, "target.hex"), "w") as fh:
        fh.write("0000\n")
    with open(os.path.join(d, "expected.json"), "w") as fh:
        json.dump({"key": 0, "malformed_only": True}, fh, indent=2)
    print("HM malformed")

    # roundtrip spot checks
    for k in (0x0000, 0x0001, 0x5A17, 0xFFFF):
        for p in (0x0000, 0x1234, 0xFFFF):
            assert decrypt(encrypt(p, k), k) == p
    print("roundtrip ok")


if __name__ == "__main__":
    main()
