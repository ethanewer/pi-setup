#!/usr/bin/env python3
import subprocess

def oracle(p):
    r = subprocess.run(['/app/cullet', 'enc', '%04X' % p], capture_output=True, text=True)
    return int(r.stdout.strip(), 16)

def oracle_challenge():
    r = subprocess.run(['/app/cullet', 'challenge'], capture_output=True, text=True)
    return int(r.stdout.strip(), 16)

def S(y): return (y * 7 + 3) & 0xFF
def SINV(y): return (183 * ((y - 3) & 0xFF)) & 0xFF
def ROL(x, n): return ((x << n) | (x >> (8 - n))) & 0xFF

# --- recover laneA table: high byte of enc(H<<8 | 0) == laneA(H)
TA = [0] * 256
for h in range(256):
    TA[h] = (oracle((h << 8) | 0) >> 8) & 0xFF
a0 = TA[0]
# --- recover laneB: low byte of enc(0x00L) == a0 ^ laneB(L)
TB = [0] * 256
for lo in range(256):
    TB[lo] = ((oracle(lo) & 0xFF) ^ a0) & 0xFF

def solve_lane(lanevals, shift):
    # lane(x) = S(S(ROL(x,shift) ^ ea) ^ eb).  Build G over the rotated argument.
    G = [lanevals[ROL(x, (8 - shift) & 7)] for x in range(256)]
    for eb in range(256):
        ea = None
        ok = True
        for x in range(256):
            Bx = SINV((SINV(G[x]) ^ eb) & 0xFF)
            v = (x ^ Bx) & 0xFF
            if ea is None:
                ea = v
            elif v != ea:
                ok = False
                break
        if ok:
            return ea, eb
    raise RuntimeError('no subkey solved')

K0, K1 = solve_lane(TA, 1)
K2, K3 = solve_lane(TB, 2)
key = (K0 << 24) | (K1 << 16) | (K2 << 8) | K3

def enc_key(p):
    h = (p >> 8) & 0xFF; l = p & 0xFF
    a = S(S(ROL(h, 1) ^ K0) ^ K1)
    b = S(S(ROL(l, 2) ^ K2) ^ K3)
    return 0xFFFF & ((a << 8) | (a ^ b))

# verify functional equivalence with the live oracle on 256 random+edge queries
import random
random.seed(2024)
trials = list(range(0, 65536, 256)) + [random.randrange(65536) for _ in range(300)]
for p in trials:
    if enc_key(p) != oracle(p):
        raise SystemExit('SOLVE FAILED equivalence')
# recover challenge plaintext
ct = oracle_challenge()
found = None
for p in range(65536):
    if enc_key(p) == ct:
        found = p
        break
if found is None:
    raise SystemExit('SOLVE FAILED decrypt')
open('/app/key.txt', 'w').write('%08x' % key + '\n')
open('/app/recovered.txt', 'w').write('%04X' % found + '\n')
print('recovered key', '%08x' % key, 'plaintext', '%04X' % found)