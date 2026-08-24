#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/btree.json" ] && [ -f "$APP/sorted_keys.txt" ]; then
  if python3 - "$APP" <<'PY'
import json, sys
base = sys.argv[1]
tree = json.load(open(base + '/btree.json'))

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
exp = [str(k) for k in out]
got = [l.rstrip('\n') for l in open(base + '/sorted_keys.txt') if l.strip() != '']
sys.exit(0 if got == exp else 1)
PY
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt