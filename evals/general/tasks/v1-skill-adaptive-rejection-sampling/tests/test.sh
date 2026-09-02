#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.json ]; then
  if python3 - <<'EOF'
import json, sys
exp = {"log_concave_required": True, "pw_linear_log_envelope": True,
       "unnormalized_allowed": True, "requires_gaussian": False}
got = json.load(open('/app/answer.json'))
for k, v in exp.items():
    if str(got.get(k)).strip().lower() != str(v).lower():
        sys.exit("bad %s" % k)
sys.exit(0)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt