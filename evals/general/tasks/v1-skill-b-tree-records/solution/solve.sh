#!/bin/bash
set -euo pipefail
cat > /app/scan_btree.py <<'PYEOF'
import json
with open('/app/btree.json') as f:
    tree = json.load(f)

def inorder(node, out):
    ks = node.get('keys', [])
    ch = node.get('children', [])
    m = len(ks)
    for i in range(m):
        if ch:
            inorder(ch[i], out)
        out.append(ks[i])
    if ch:
        inorder(ch[m], out)

out = []
inorder(tree['root'], out)
with open('/app/sorted_keys.txt', 'w') as f:
    for k in out:
        f.write(str(k) + chr(10))
PYEOF
python3 /app/scan_btree.py
