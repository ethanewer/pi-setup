#!/bin/bash
set -euo pipefail

cat > /app/organize.py <<'PYEOF'
import os, json, shutil

src = '/app/loose'
dst = '/app/organized'
manifest = {}

for name in sorted(os.listdir(src)):
    path = os.path.join(src, name)
    if not os.path.isfile(path):
        continue
    ext = os.path.splitext(name)[1].lstrip('.')
    if not ext:
        continue
    target_dir = os.path.join(dst, ext)
    os.makedirs(target_dir, exist_ok=True)
    os.replace(path, os.path.join(target_dir, name))
    manifest.setdefault(ext, []).append(name)

for k in manifest:
    manifest[k].sort()

with open('/app/manifest.json', 'w') as f:
    json.dump(manifest, f)
PYEOF

python3 /app/organize.py