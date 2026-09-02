#!/bin/bash
set -euo pipefail

cat > /app/cipher.py <<'PYEOF'
import json

def rot(x):
    return ((x << 2) | (x >> 6)) & 0xFF

def F(R, K):
    return [rot((R[i] + K[i]) & 0xFF) for i in range(4)]

def xor(a, b):
    return [a[i] ^ b[i] for i in range(4)]

KEYS = [
    [0x12, 0x23, 0x45, 0x67],
    [0x89, 0xAB, 0xCD, 0xEF],
    [0xFE, 0xDC, 0xBA, 0x98],
    [0x76, 0x54, 0x32, 0x10],
]

def encrypt(block):
    L = list(block[0:4])
    R = list(block[4:8])
    for i in range(4):
        newL = R
        newR = xor(L, F(R, KEYS[i]))
        L, R = newL, newR
    return bytes(L + R)

plain = open('/app/plaintext.bin', 'rb').read()
cipher_bytes = encrypt(plain)
open('/app/cipher.bin', 'wb').write(cipher_bytes)

out = {
    'plaintext': plain.hex(),
    'ciphertext': cipher_bytes.hex(),
}
with open('/app/cipher.json', 'w') as f:
    json.dump(out, f)
PYEOF

python3 /app/cipher.py