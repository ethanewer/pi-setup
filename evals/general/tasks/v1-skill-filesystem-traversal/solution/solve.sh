#!/bin/bash
set -euo pipefail

cat > /app/traverse.py <<'PYEOF'
import os, json

root = '/app/tree'
dirs = 0
files = 0
total_bytes = 0
log_files = 0
log_bytes = 0

for base, dirnames, filenames in os.walk(root):
    dirs += len(dirnames)
    for fn in filenames:
        files += 1
        size = os.path.getsize(os.path.join(base, fn))
        total_bytes += size
        if fn.endswith('.log'):
            log_files += 1
            log_bytes += size

out = {
    'dirs': dirs,
    'files': files,
    'total_bytes': total_bytes,
    'log_files': log_files,
    'log_bytes': log_bytes,
}
with open('/app/tree.json', 'w') as f:
    json.dump(out, f)
PYEOF

python3 /app/traverse.py