#!/bin/bash
mkdir -p /logs/verifier
reward=0
exp=$(python3 - <<'EOF' 2>/dev/null
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
print(caesar(ct, -k))
EOF
)
if [ -n "$exp" ] && [ -f /app/decoded.txt ]; then
  got=$(python3 -c "print(open('/app/decoded.txt').read().strip())" 2>/dev/null)
  if [ "$got" = "$exp" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt