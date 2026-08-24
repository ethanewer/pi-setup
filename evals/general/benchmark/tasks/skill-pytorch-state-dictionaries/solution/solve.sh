#!/bin/bash
set -euo pipefail
python3 - <<'PY'
import torch
model=torch.nn.Linear(3,2)
model.load_state_dict(torch.load('/app/policy.pt'))
x=torch.tensor([1.0,2.0,3.0])
y=model(x).tolist()
with open('/app/out.txt','w') as f:
    for v in y:
        r=round(v,1)
        if r==int(r):
            f.write("%.1f\n" % r)
        else:
            f.write(str(r)+"\n")
print(y)
PY
