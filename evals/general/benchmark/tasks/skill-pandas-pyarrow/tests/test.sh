#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/out.parquet ] && [ -f /app/sums.txt ] && [ -f /app/data.csv ]; then
python3 - <<'PYEOF'
import sys
try:
    import pandas as pd
    def is_pyarrow(ser):
        d = ser.dtype
        if isinstance(d, pd.ArrowDtype):
            return 'pyarrow' in repr(d)
        if isinstance(d, pd.StringDtype):
            return getattr(d, 'storage', None) == 'pyarrow'
        return 'pyarrow' in repr(d)

    s = pd.read_csv('/app/data.csv').groupby('region', sort=False)['amount'].sum().sort_values(ascending=False)
    exp = [f"{k} {int(v)}" for k, v in s.items()]
    got = [l.strip() for l in open('/app/sums.txt') if l.strip()]

    df = pd.read_parquet('/app/out.parquet')
    ok = (
        got == exp
        and is_pyarrow(df['region'])
        and is_pyarrow(df['amount'])
        and len(df) == 6
        and df.columns.to_list() == ['region', 'amount']
    )
    sys.exit(0 if ok else 1)
except Exception:
    sys.exit(1)
PYEOF
  if [ $? -eq 0 ]; then reward=1; fi
fi
echo "$reward" > /logs/verifier/reward.txt