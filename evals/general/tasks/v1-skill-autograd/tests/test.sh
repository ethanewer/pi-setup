#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.json ] && [ -f /app/solve.py ]; then
  if grep -q "autograd" /app/solve.py; then
    if python3 - <<'EOF'
import json, math, sys
got=json.load(open('/app/answer.json'))
exp_dx = 2*2.0*3.0 - math.sin(2.0)   # 2xy - sin(x) at (2,3)
exp_dy = 4.0
df_dx=float(got.get('df_dx')); df_dy=float(got.get('df_dy'))
if abs(df_dx-exp_dx) > 1e-2 or abs(df_dy-exp_dy) > 1e-2:
    sys.exit("mismatch got=(%r,%r) exp=(%r,%r)"% (df_dx,df_dy,exp_dx,exp_dy))
sys.exit(0)
EOF
    then
      reward=1
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt