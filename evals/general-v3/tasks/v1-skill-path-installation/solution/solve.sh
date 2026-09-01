#!/bin/bash
set -euo pipefail
mkdir -p /app/vendor
cp -r /app/mytool /app/vendor/
cat > /app/use.py <<'PYEOF'
import sys
sys.path.insert(0, '/app/vendor')
import mytool.greet as greet
result = greet.hello('world')
with open('/app/out.txt', 'w') as f:
    f.write(result + '\n')
PYEOF
python3 /app/use.py
echo "wrote /app/use.py and /app/out.txt"