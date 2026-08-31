#!/bin/bash
# Oracle for myrtle-canyon: install MuJoCo offline from the vendored
# wheelhouse, tune the reference feed-stage model into /app/tuned-model.xml
# (self-contained, plugin-free), simulate the acceptance case, and write the
# MUJOCO_OK report. The reference file is never touched. Never reads /tests.
set -eu

# ---- 1. Fresh offline MuJoCo installation from the pinned wheelhouse.
pip install --no-index --find-links /app/wheelhouse mujoco==3.2.4 >/dev/null
python3 -c "import mujoco; assert mujoco.__version__ == '3.2.4', mujoco.__version__"

# ---- 2. Tuned model: stronger actuator gearing, light joint damping.
# Same single slide joint 'feed' + single motor 'drive'; no plugins, no
# assets, no includes — a fully self-contained MJCF.
cat > /app/tuned-model.xml <<'EOF'
<mujoco model="feed-stage-tuned">
  <worldbody>
    <body name="carriage" pos="0 0 0">
      <joint name="feed" type="slide" axis="1 0 0" damping="0.05"/>
      <geom name="block" type="box" size="0.08 0.05 0.03" mass="1.0"/>
    </body>
  </worldbody>
  <actuator>
    <motor name="drive" joint="feed" gear="1.5"/>
  </actuator>
</mujoco>
EOF

# ---- 3. Acceptance simulation on the visible drive (2.0 s, ctrl = 2.0).
python3 - <<'PY' > /tmp/myrtle_sweep.txt
import mujoco

def sweep(path, ctrl, secs=2.0):
    m = mujoco.MjModel.from_xml_path(path)
    d = mujoco.MjData(m)
    d.ctrl[0] = ctrl
    mx = 0.0
    for _ in range(round(secs / m.opt.timestep)):
        mujoco.mj_step(m, d)
        mx = max(mx, abs(d.qpos[0]))
    return mx, m.nplugin

tuned_mx, npl = sweep("/app/tuned-model.xml", 2.0)
ref_mx, _ = sweep("/app/ref-model.xml", 2.0)
assert tuned_mx > 0.35, tuned_mx
assert ref_mx < 0.10, ref_mx
print("%.6f %d" % (tuned_mx, npl))
PY

SWEEP="$(cut -d' ' -f1 /tmp/myrtle_sweep.txt)"
NPL="$(cut -d' ' -f2 /tmp/myrtle_sweep.txt)"

# ---- 4. Proof-of-simulation report deliverable.
cat > /app/sim-report.txt <<EOF
MUJOCO_OK install=wheelhouse-3.2.4 plugins=$NPL sweep=$SWEEP
visible drive: ctrl=2.0 for 2.0s at default timestep
tuned max |qpos[0]| = $SWEEP m; reference stayed below 0.10 m
EOF

echo "solve.sh done"
ls -l /app/tuned-model.xml /app/sim-report.txt
cat /app/sim-report.txt
