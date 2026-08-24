#!/bin/bash
set -euo pipefail
python3 - <<'PYEOF'
from cryptography.hazmat.primitives.serialization import load_pem_public_key
key = load_pem_public_key(open('/app/certificate.pem', 'rb').read())
e = key.public_numbers().e
open('/app/answer.txt', 'w').write(str(e) + '\n')
print("wrote /app/answer.txt with public exponent e =", e)
PYEOF