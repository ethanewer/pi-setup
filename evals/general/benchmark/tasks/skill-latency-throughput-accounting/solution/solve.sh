#!/bin/bash
set -euo pipefail
python3 - <<'EOF'
import json
recs = json.load(open('/app/transfers.json'))
total_bytes = sum(r['bytes'] for r in recs)
total_dur   = sum(r['duration_sec'] for r in recs)
avg_lat     = total_dur / len(recs)
out = {
    "throughput_bps": round(total_bytes / total_dur, 3),
    "avg_latency_sec": round(avg_lat, 3),
}
with open('/app/metrics.json','w') as f:
    json.dump(out, f)
print(out)
EOF