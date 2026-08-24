#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/model/pendulum.xml ] && [ -f /app/report.txt ]; then
  if python3 - <<'PYEOF'
import xml.etree.ElementTree as ET, sys
tree = ET.parse('/app/model/pendulum.xml')
root = tree.getroot()
assert root.tag == 'mujoco'
slider = None
bodies = [b for b in root.iter('body') if b.get('name') == 'slider']
assert len(bodies) == 1, 'slider body missing'
slider = bodies[0]
j0_joints = [j for j in slider.iter('joint') if j.get('name') == 'j0']
assert len(j0_joints) == 1, 'joint j0 missing'
assert j0_joints[0].get('type') == 'slide', 'j0 not slide'
geoms = [g for g in slider.iter('geom') if g.get('type') in ('box','sphere','capsule')]
assert geoms, 'no valid geom type'
report = open('/app/report.txt').read().strip()
assert report == 'joint type slide', report
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt