#!/bin/bash
set -euo pipefail

cat > /app/make_exact.py <<'PYEOF'
hexstr = "65786163742d6f757470757400ff01ff0a4142"
data = bytes.fromhex(hexstr)
with open("/app/exact.bin", "wb") as f:
    f.write(data)
PYEOF

python3 /app/make_exact.py