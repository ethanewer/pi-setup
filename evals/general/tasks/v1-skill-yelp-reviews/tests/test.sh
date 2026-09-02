#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/reviews.tsv" ] && [ -f "$APP/review_summary.json" ]; then
  if python3 - "$APP" <<'PYEOF'
import csv, json, sys
from collections import defaultdict
base = sys.argv[1]
with open(base + '/reviews.tsv') as f:
    rows = list(csv.DictReader(f, delimiter='\t'))
sums = defaultdict(int); counts = defaultdict(int)
total = 0; total_sum = 0
for r in rows:
    biz = r['business_id']; rat = int(r['rating'])
    sums[biz] += rat; counts[biz] += 1
    total += 1; total_sum += rat
per = {b: round(sums[b] / counts[b], 2) for b in sums}
exp = {"per_business": per, "total_reviews": total,
       "overall_average": round(total_sum / total, 2)}
try:
    got = json.load(open(base + '/review_summary.json'))
except Exception:
    sys.exit(1)
if got.get('total_reviews') != exp['total_reviews']:
    sys.exit(1)
if abs(float(got.get('overall_average', 0)) - exp['overall_average']) > 1e-6:
    sys.exit(1)
g = got.get('per_business')
if not isinstance(g, dict) or set(g.keys()) != set(exp['per_business'].keys()):
    sys.exit(1)
for k in exp['per_business']:
    if abs(float(g[k]) - exp['per_business'][k]) > 1e-6:
        sys.exit(1)
sys.exit(0)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt