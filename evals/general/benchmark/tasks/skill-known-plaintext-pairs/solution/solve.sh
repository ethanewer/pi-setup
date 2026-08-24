#!/bin/bash
set -euo pipefail
python3 - <<'EOF'
def shift_char(c, k):
    if 'A' <= c <= 'Z':
        return chr((ord(c) - ord('A') + k) % 26 + ord('A'))
    return c

def caesar(s, k):
    return ''.join(shift_char(c, k) for c in s)

p = open('/app/known_plain.txt').read().strip()
c = open('/app/known_cipher.txt').read().strip()
k = (ord(c[0]) - ord(p[0])) % 26
ct = open('/app/ciphertext.txt').read().strip()
dec = caesar(ct, -k)
open('/app/decoded.txt', 'w').write(dec + '\n')
print("key", k, "decoded", dec)
EOF