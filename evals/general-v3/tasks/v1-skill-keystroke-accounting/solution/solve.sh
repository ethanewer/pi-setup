#!/bin/bash
set -euo pipefail
python3 - <<'EOF'
import json
d = json.load(open('/app/keylog.json'))
tot = sum(e['press'] for e in d['events'])
distinct = len({e['key'] for e in d['events']})
with open('/app/keylog_summary.json','w') as f:
    json.dump({"total_keystrokes": tot, "distinct_keys": distinct}, f)
print("total", tot, "distinct", distinct)
EOF