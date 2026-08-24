#!/bin/bash
set -euo pipefail

make --directory=/app run > /tmp/gcovrun.out

# gcov prints a line-coverage summary (e.g. "Lines executed:90.00% of 10") at
# the end of its run; parse the percentage from that summary line.
python3 - <<'EOF'
import re, json
out = open('/tmp/gcovrun.out').read()
m = re.search(r'Lines executed:([0-9.]+)% of ([0-9]+)', out)
assert m, out
percent = round(float(m.group(1)), 1)
with open('/app/coverage.json', 'w') as f:
    json.dump({"coverage_percent": percent}, f)
EOF