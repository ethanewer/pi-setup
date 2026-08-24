#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/data.parquet ] && [ -f /app/answer.txt ] && [ -f /app/data.csv ]; then
python3 - <<'PYEOF'
import sys
try:
    import pandas as pd
    import pyarrow.parquet as pq

    src = pd.read_csv('/app/data.csv')
    total = int(src['temp'].sum())

    pf = pq.ParquetFile('/app/data.parquet')
    names = pf.schema.names
    rows = pf.metadata.num_rows

    back = pd.read_parquet('/app/data.parquet')
    ans = open('/app/answer.txt').read().strip()

    ok = (
        names == ['id', 'city', 'temp']
        and rows == len(src)
        and back['temp'].astype('int64').tolist() == src['temp'].astype('int64').tolist()
        and back['id'].astype('int64').tolist() == src['id'].astype('int64').tolist()
        and ans == str(total)
    )
    sys.exit(0 if ok else 1)
except Exception:
    sys.exit(1)
PYEOF
  if [ $? -eq 0 ]; then reward=1; fi
fi
echo "$reward" > /logs/verifier/reward.txt