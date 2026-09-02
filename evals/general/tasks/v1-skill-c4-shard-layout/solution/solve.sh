#!/usr/bin/env bash
set -euo pipefail

cat > /app/c4_analyze.py <<'PY_END'
import gzip, json, os, sys

d = "/app/c4"
files = sorted(f for f in os.listdir(d) if f.endswith(".json.gz"))

records = 0
per_shard = None
indices = []
for f in files:
    stem = f[:-len(".json.gz")]
    body, total = stem.rsplit("-of-", 1)
    idx = int(body.split(".")[-1])
    indices.append(idx)
    with gzip.open(os.path.join(d, f), "rt") as fh:
        n = sum(1 for _ in fh)
    per_shard = n if per_shard is None else per_shard
    records += n

summary = {
    "split": "c4-train",
    "shard_total": 1024,
    "shards_present": len(files),
    "records_per_shard": per_shard,
    "total_records": records,
    "min_index": min(indices),
    "max_index": max(indices),
    "missing_count": 1024 - len(files),
}
with open("/app/c4_summary.json", "w") as fh:
    json.dump(summary, fh)
print(summary)
PY_END

python3 /app/c4_analyze.py
python3 -c "import json; d=json.load(open('/app/c4_summary.json')); assert d['total_records'] == 32 and d['shards_present'] == 8"