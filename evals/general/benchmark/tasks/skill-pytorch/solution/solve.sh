#!/bin/bash
set -euo pipefail
python3 - <<'PY'
import torch
t=torch.load('/app/values.pt')
s=int(t.sum().item())
open('/app/sum.txt','w').write(str(s))
print("sum:", s)
PY
