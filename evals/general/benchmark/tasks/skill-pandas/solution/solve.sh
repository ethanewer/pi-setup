#!/bin/bash
set -euo pipefail
python3 - <<'PYEOF'
import pandas as pd
df = pd.read_csv('/app/data.csv')
s = df.groupby('region', sort=False)['amount'].sum().sort_values(ascending=False)
out = s.reset_index()
out.columns = ['region', 'total']
out.to_csv('/app/summary.csv', index=False)
print("wrote /app/summary.csv")
PYEOF
