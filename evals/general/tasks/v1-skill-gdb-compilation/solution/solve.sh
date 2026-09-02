#!/bin/bash
set -euo pipefail

gcc -g -O0 /app/debug.c -o /app/debug_bin

cat > /app/dbgscript <<'X'
break /app/debug.c:11
run
print checksum
quit
X

gdb -q /app/debug_bin -x /app/dbgscript > /app/gdb_out.txt 2>&1

python3 - <<'EOF'
import re, json
out = open('/app/gdb_out.txt').read()
vals = re.findall(r'\$[0-9]+\s*=\s*(-?[0-9]+)', out)
assert vals, out
with open('/app/debugged.json','w') as f:
    json.dump({"checksum": int(vals[-1])}, f)
EOF