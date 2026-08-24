#!/usr/bin/env bash
mkdir -p /logs/verifier

reward=0
if python3 - <<'PY_END'
import gzip, json, os, sys

# Recompute ground truth from the shard files themselves.
d = "/app/c4"
files = sorted(f for f in os.listdir(d) if f.endswith(".json.gz"))
assert len(files) > 0, "no shards found"

records = 0
per_shard = None
indices = []
totals = set()
for f in files:
    stem = f[:-len(".json.gz")]
    # c4-train.00000-of-01024  -> index=0, total=1024
    body, total = stem.rsplit("-of-", 1)  # split on last '-of-'
    idx = int(body.split(".")[-1])
    indices.append(idx)
    totals.add(int(total))
    with gzip.open(os.path.join(d, f), "rt") as fh:
        n = 0
        for line in fh:
            obj = json.loads(line)
            assert "text" in obj and "url" in obj
            n += 1
        per_shard = n if per_shard is None else per_shard
        assert n == per_shard, "uneven shard sizes"
        records += n

expected = {
    "split": "c4-train",
    "shard_total": 1024,
    "shards_present": len(files),
    "records_per_shard": per_shard,
    "total_records": records,
    "min_index": min(indices),
    "max_index": max(indices),
    "missing_count": 1024 - len(files),
}
try:
    got = json.load(open("/app/c4_summary.json"))
except Exception:
    sys.exit(1)
for k, v in expected.items():
    if got.get(k) != v:
        sys.exit(1)
sys.exit(0)
PY_END
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt