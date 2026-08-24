#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/qpos.txt ]; then
  if python3 - <<'PYEOF'
import mujoco

model = mujoco.MjModel.from_xml_path('/app/model/box.xml')
data = mujoco.MjData(model)
for _ in range(30):
    mujoco.mj_step(model, data)

expected = [round(float(data.qpos[i]), 3) for i in range(3)]

with open('/app/qpos.txt') as f:
    parts = f.read().strip().split()
got = [float(x) for x in parts]
assert len(parts) == 3, parts
for a, b in zip(got, expected):
    assert abs(a - b) < 0.001, (got, expected)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt