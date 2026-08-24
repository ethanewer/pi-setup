#!/bin/bash
set -euo pipefail
# recompute hierarchical posterior mean from /app/hier_model.txt constants
python3 - <<'PYEOF'
vals = {}
for line in open('/app/hier_model.txt'):
    k, v = line.strip().split('=')
    vals[k] = float(v)
post_prec = vals['pi0'] + vals['piA'] + vals['piB']
post_mean = (vals['pi0']*vals['mu0'] + vals['piA']*vals['mA'] + vals['piB']*vals['mB']) / post_prec
open('/app/answer.txt','w').write(repr(post_mean) + '\n')
PYEOF