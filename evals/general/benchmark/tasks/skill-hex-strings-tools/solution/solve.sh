#!/bin/bash
set -euo pipefail
# recover the printable ASCII run from the binary blob
python3 - <<'PYEOF'
import re
data = open('/app/blob.bin','rb').read()
tok = re.search(rb'[A-Za-z0-9_\-!@#$%^&*()+=\[\]{};:,./<>?`~]+', data).group(0).decode('ascii')
open('/app/token.txt','w').write(tok + '\n')
PYEOF