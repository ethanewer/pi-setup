In `/app/model` there is a MuJoCo model file `box.xml`. It contains a single body named `b` connected to the world by a `freejoint`, with a spherical geometry.

The `mujoco` Python package is already installed.

Write a Python script `/app/sim.py` that:

1. Loads the model from `/app/model/box.xml` with `mujoco.MjModel.from_xml_path`.
2. Creates an actuator-free `MjData` state for it.
3. Advances the simulation forward exactly **30 physics steps** using `mujoco.mj_step(model, data)`.
4. Reads the resulting translational position of the body from `data.qpos`, which has 7 entries for a free joint (3 translation + 4 quaternion). Take the first three `qpos` entries (the x, y, z translation in metres).
5. Rounds each of those three values to 3 decimals with Python's built-in `round(v, 3)` and writes `/app/qpos.txt` containing exactly one line:

```
<x> <y> <z>
```

(the three rounded numbers separated by single spaces, numbers in decimal metre units).

Run the script so `/app/qpos.txt` exists with the correct contents.