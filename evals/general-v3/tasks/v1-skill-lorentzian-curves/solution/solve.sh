#!/bin/bash
set -euo pipefail
python3 - <<'EOF'
import json, math
x0,gamma,A=5.0,0.8,2.0
json.dump({"fwhm":2*gamma,"peak_height":A/(math.pi*gamma)}, open('/app/answer.json','w'))
EOF