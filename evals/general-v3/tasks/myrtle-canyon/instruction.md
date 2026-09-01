# myrtle-canyon — bring MuJoCo up offline and tune the feed stage

The **Myrtle Canyon** motion lab needs its linear feed stage simulated. Two
problems: the box has **no MuJoCo installation at all** (only a pinned offline
wheelhouse), and the shipped reference model barely moves under drive. Your
job: install MuJoCo from the vendored wheels, tune the model into a second
file, and prove both under a clean, plugin-free simulation — **without ever
touching the reference file**.

## Fixtures already in `/app`

- `/app/ref-model.xml` — the reference MJCF: a carriage on a slide joint
  (`feed`, axis x) driven by one `motor` actuator (`drive`). **Must remain
  byte-for-byte identical** to what shipped (the grader compares against a
  pristine copy it holds).
- `/app/wheelhouse/` — a pinned offline wheelhouse containing
  `mujoco==3.2.4` and every wheel it needs. The machine has no network; the
  ONLY supported way to install is:
  ```
  pip install --no-index --find-links /app/wheelhouse mujoco==3.2.4
  ```
  Do not download anything; do not install a different version.

## Deliverables

1. **`/app/tuned-model.xml`** — your tuned feed-stage model. Requirements:
   - Single **self-contained** MJCF: no `<plugin>` elements, no plugins of any
     kind, no `<include>`, no `<asset>`/mesh/textures, no `meshdir`/
     `texturedir`. Keep exactly **one slide joint** named `feed` and **one
     motor actuator** named `drive` (the grader reads `qpos[0]` and
     `ctrl[0]`).
   - Must differ from the reference (bytes differ).
   - Loading it fresh with `mujoco.MjModel.from_xml_path('/app/tuned-model.xml')`
     must work with no extra files anywhere, and the loaded model must report
     **zero plugins**.
2. **`/app/sim-report.txt`** — your proof-of-simulation note; its **first
   line must start with the token `MUJOCO_OK`**, e.g.
   ```
   MUJOCO_OK install=wheelhouse-3.2.4 plugins=0 sweep=5.81
   ```
   (subsequent lines free-form).

## The tuning acceptance (checked under simulation)

At the model's **default timestep**, for a constant drive `d.ctrl[0] = c`
applied for **2.0 simulated seconds**:

- the **tuned** model's carriage must sweep to `|qpos[0]| > 0.35` m at some
  point during the run;
- the **reference** model under the same drive must stay **below
  `|qpos[0]| < 0.10`** m the whole run.

This must hold for the visible drive `c = 2.0` **and** for hidden drives you
have not seen (positive and negative, mild and strong) — so tune the physics
(gear, damping, mass…), not a simulation artifact. The acceptance simulation
is exactly:

```python
import mujoco
m = mujoco.MjModel.from_xml_path(path)
d = mujoco.MjData(m)
d.ctrl[0] = c
for _ in range(round(2.0 / m.opt.timestep)):
    mujoco.mj_step(m, d)
    track max |d.qpos[0]|
```

Run the visible case yourself and record the observed sweep in
`/app/sim-report.txt`.

## How the grader probes it

- Verifies `/app/ref-model.xml` is byte-identical to the pristine reference.
- Verifies MuJoCo 3.2.4 imports (a **fresh installation** from your
  wheelhouse work), and re-executes the acceptance simulation on the visible
  drive and on **hidden drive sets** (each hidden case lists drives plus the
  same 0.35/0.10 thresholds) against **both** models.
- Verifies the tuned model is self-contained and plugin-free (XML scan and
  the loaded model's plugin count), and differs from the reference.
- Verifies `/app/sim-report.txt` starts with `MUJOCO_OK`.

Rules: no network; do not modify `/app/ref-model.xml` or `/app/wheelhouse/`;
work only under `/app` plus the normal package-install locations.
