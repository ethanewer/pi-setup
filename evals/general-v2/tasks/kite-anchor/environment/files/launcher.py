#!/usr/bin/env python3
"""launcher.py — FK81 release harness.

The physical model team ships a *reference* greedy autoregressive arg-max
sampler written in Python.  The C port (kite_app.c built to ./app) must agree
with this reference byte-for-byte because the harness runs `app sample <LEN>
<SEED>` through THIS launcher and checks the stdout contract.

Usage:
    python3 launcher.py sample <LEN> <SEED>
        spawns ./app sample <LEN> <SEED>, compares its stdout to the
        reference greedy tokens, prints "LAUNCH_OK <LEN> <SEED>" on a match
        or "LAUNCH_FAIL <LEN> <SEED>" otherwise (exit 0 / 1).
    python3 launcher.py key <SEED>
        prints the reference 8-letter activation code for <SEED> (does not
        spawn; used by the verifier's from-source rebuild check).
"""
import subprocess
import sys

MASK32 = 0xFFFFFFFF


def lcg(s):
    return (s * 1664525 + 1013904223) & MASK32


def sample(seed, length):
    """Greedy autoregressive arg-max sampler, 26-char alphabet 'a'..'z'."""
    s = seed & MASK32
    out = []
    prev = -1
    for _ in range(length):
        s = lcg(s)
        best = -1
        bestsc = -1
        for tok in range(26):
            s2 = lcg((s ^ (tok * 2654435761)) & MASK32)
            sc = (prev << 3) + tok + 1024
            sc2 = (sc * 31 + (s2 & 0xFF)) % 1000003
            if sc2 > bestsc:
                bestsc = sc2
                best = tok
        out.append(chr(ord('a') + best))
        prev = best
    return ''.join(out)


def main():
    if len(sys.argv) < 2:
        print("usage: launcher.py sample <LEN> <SEED> | key <SEED>")
        return 2
    mode = sys.argv[1]
    if mode == 'key':
        seed = int(sys.argv[2])
        print(sample(seed, 8))
        return 0
    # sample
    length = int(sys.argv[2])
    seed = int(sys.argv[3])
    expected = sample(seed, length)
    proc = subprocess.run(['./app', 'sample', str(length), str(seed)],
                          capture_output=True, text=True, timeout=60)
    actual = (proc.stdout or '').strip()
    if proc.returncode == 0 and actual == expected:
        print("LAUNCH_OK %d %d" % (length, seed))
        return 0
    print("LAUNCH_FAIL %d %d" % (length, seed))
    return 1


if __name__ == '__main__':
    sys.exit(main())