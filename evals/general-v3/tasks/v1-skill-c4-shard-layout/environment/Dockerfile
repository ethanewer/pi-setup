FROM bench-base:python-3.12

WORKDIR /app

# Build a tiny C4-style corpus: 8 shards, each 4 JSON records (one JSON object per
# line), gzip-compressed, named with the standard C4 shard layout
#   c4-train.<index:05d>-of-<total:05d>.json.gz
RUN python3 - <<'PY_END'
import gzip, json, os
os.makedirs('/app/c4', exist_ok=True)
for s in range(8):
    name = f'c4-train.{s:05d}-of-01024.json.gz'
    with gzip.open(os.path.join('/app/c4', name), 'wt', encoding='utf-8') as fh:
        for i in range(4):
            rec = {
                'text': f'shard {s} record {i} ' + ('x' * (s * 3 + i)),
                'url': f'https://example.com/doc/{s}-{i}',
            }
            fh.write(json.dumps(rec) + '\n')
print('generated 8 shards')
PY_END