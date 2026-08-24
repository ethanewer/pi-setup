#!/bin/bash
set -euo pipefail

cat > /app/sim.py <<'EOF'
import mujoco

model = mujoco.MjModel.from_xml_path('/app/model/box.xml')
data = mujoco.MjData(model)

for _ in range(30):
    mujoco.mj_step(model, data)

q = [round(float(data.qpos[i]), 3) for i in range(3)]
with open('/app/qpos.txt', 'w') as f:
    f.write(' '.join(str(v) for v in q) + '\n')
EOF

python3 /app/sim.py