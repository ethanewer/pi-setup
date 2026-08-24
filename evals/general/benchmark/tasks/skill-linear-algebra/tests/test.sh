#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.json ]; then
  if python3 - <<'EOF'
import json
exp={"x":3.0,"y":0.0}
got=json.load(open('/app/answer.json'))
for k,v in exp.items():
    gv = got.get(k)
    if not isinstance(gv,(int,float)):
        raise SystemExit("bad type %s" % k)
    if abs(float(gv) - v) > 1e-6:
        raise SystemExit("bad value %s" % k)
print("PASS"); raise SystemExit(0)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt