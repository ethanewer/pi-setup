#!/bin/bash
set -euo pipefail

cat > /app/roundtrip.py <<'PYEOF'
import gzip

with open('/app/plain.txt', 'rb') as f:
    original = f.read()

compressed = gzip.compress(original)
with open('/app/payload.gz', 'wb') as f:
    f.write(compressed)

recovered = gzip.decompress(compressed)
assert recovered == original, "round trip mismatch"

with open('/app/recovered.txt', 'wb') as f:
    f.write(recovered)
PYEOF

python3 /app/roundtrip.py