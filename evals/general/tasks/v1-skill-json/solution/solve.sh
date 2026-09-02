#!/bin/bash
set -euo pipefail
python3 - <<'EOF'
import json
cfg = json.load(open('/app/config.json'))
port = cfg['server']['port']
open('/app/port_output.txt', 'w').write(str(port) + '\n')
print("port:", port)
EOF