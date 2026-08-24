#!/bin/bash
set -euo pipefail
python3 - <<'PY'
import re
src=open('/app/dates.txt').read()
pat=r'(?P<y>\d{4})-(?P<m>\d{2})-(?P<d>\d{2})'
out=re.sub(pat, lambda m: '%s/%s/%s'%(m.group('m'),m.group('d'),m.group('y')), src)
open('/app/rewritten.txt','w').write(out)
print(out)
PY
