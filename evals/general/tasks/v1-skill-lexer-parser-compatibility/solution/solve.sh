#!/bin/bash
set -euo pipefail
python3 - <<'EOF'
import json, re
rules = json.load(open('/app/lexer_rules.json'))['rules']
src = open('/app/input.txt').read().strip()
names = []
pos = 0
while pos < len(src):
    best = None
    for r in rules:
        m = re.compile(r['pattern']).match(src, pos)
        if m and (best is None or m.end() - pos > best[1]):
            best = (r['name'], m.end() - pos)
    if best is None:
        raise SystemExit('lex error at %d' % pos)
    names.append(best[0])
    pos += best[1]
with open('/app/token_sequence.json','w') as f:
    json.dump(names, f)
print(names)
EOF