#!/bin/bash
set -euo pipefail
python3 - <<'PYEOF'
import re
html = open('/app/index.html', encoding='utf-8').read()
# find every distribution filename announced by the index: demo-<version>-py3-none-any.whl
vers = []
for m in re.finditer(r'demo-([0-9]+(?:\.[0-9]+)*)-py3-none-any\.whl', html):
    vers.append(tuple(int(x) for x in m.group(1).split('.')))
latest = max(vers)
version_str = '.'.join(str(x) for x in latest)
open('/app/version.txt', 'w').write(version_str + '\n')
print("newest demo version:", version_str)
PYEOF