#!/bin/bash
set -euo pipefail

mkdir -p /app/report

python3 - <<'PY'
import os, json, re

found = {}
for dirpath, _, files in os.walk('/app'):
    for fn in files:
        path = os.path.join(dirpath, fn)
        try:
            txt = open(path, encoding='utf-8', errors='ignore').read()
        except Exception:
            continue
        m = re.search(r'(token_[A-Za-z0-9_]+)', txt)
        if m:
            rel = os.path.relpath(path, '/app')
            keyname = None
            for line in txt.splitlines():
                if 'token_EXAMPLE' in line:
                    mm = re.match(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*[=:]', line)
                    if mm:
                        keyname = mm.group(1)
            found = {"file": rel, "key": keyname, "secret": m.group(1)}
            break

assert found, "no secret found"
with open('/app/report/secret.json', 'w') as f:
    json.dump(found, f)
print(found)
PY