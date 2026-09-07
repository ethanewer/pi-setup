#!/usr/bin/env bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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