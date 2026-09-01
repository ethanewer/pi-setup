#!/usr/bin/env bash
mkdir -p /logs/verifier

reward=0
if python3 - <<'PY_END'
import json, sys
sys.path.insert(0, "/app")
try:
    import numc
    assert numc.add(30, 12) == 42
    assert abs(numc.mul(6.0, 7.0) - 42.0) < 1e-9
    d = json.load(open("/app/out.json"))
    assert d == {"add": 42, "mul": 42.0}
except Exception:
    sys.exit(1)
sys.exit(0)
PY_END
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt