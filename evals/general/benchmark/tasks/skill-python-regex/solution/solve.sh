#!/bin/bash
set -euo pipefail
python3 - <<'PY'
import re
src=open('/app/colors.txt').read()
toks=re.findall(r'#[0-9A-Fa-f]{6}', src)
s=sum(int(t[1:],16) for t in toks)
open('/app/answer.txt','w').write(str(s))
print("tokens:", toks, "sum:", s)
PY
