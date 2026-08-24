#!/bin/bash
set -euo pipefail

cat > /app/rle.py <<'PY'
import sys

s = open('/app/input.txt').read().strip()
out = []
i = 0
while i < len(s):
    j = i
    while j < len(s) and s[j] == s[i]:
        j += 1
    out.append(s[i] + str(j - i))
    i = j
open('/app/encoded.txt', 'w').write(''.join(out))
print('encoded:', ''.join(out))
PY

python3 /app/rle.py