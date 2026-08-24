#!/bin/bash
set -euo pipefail
python3 - <<'PYEOF'
import pandas as pd
df = pd.read_csv('/app/data.csv')
df.to_parquet('/app/data.parquet', engine='pyarrow')
total = int(df['temp'].sum())
open('/app/answer.txt', 'w').write(str(total))
print("wrote /app/data.parquet and /app/answer.txt")
PYEOF