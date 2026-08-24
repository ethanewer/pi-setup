#!/bin/bash
set -euo pipefail
python3 - <<'PYEOF'
import pandas as pd
df = pd.read_csv('/app/data.csv', dtype_backend='pyarrow')
df.to_parquet('/app/out.parquet', engine='pyarrow')
s = df.groupby('region', sort=False)['amount'].sum().sort_values(ascending=False)
lines = [f"{k} {int(v)}" for k, v in s.items()]
with open('/app/sums.txt', 'w') as f:
    f.write("\n".join(lines) + "\n")
print("wrote out.parquet and sums.txt")
PYEOF