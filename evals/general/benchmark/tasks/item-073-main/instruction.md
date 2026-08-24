# Optimize a MuJoCo simulation without changing its physics (item-073)

`/app/arm.xml` is a plain **double-pendulum** MJCF model (two revolute joints,
gravity-driven, no actuators). `/app/simulate.py` is a *semantically correct*
baseline: it compiles the model and steps a continuous trajectory, but it is
deliberately **slow** because it recompiles the whole MJCF model from the XML
string inside the step loop.

Your job is to produce `/app/optimize.py` that simulates the **exact same
physics** (same model, same initial state, same timestep, same number of steps)
but runs at least **4x faster in wall-clock time** than `/app/simulate.py`, with
**no NaN/Inf** anywhere in the recorded state.  You must keep the maths intact —
do not change the model, the integration timestep, the solver options, or the
initial condition.  Optimize the *implementation*, not the physics.

## Contract (fixed, do not deviate)

- JXML is `/app/arm.xml`. Its timestep is `dt` (from the model).
- Start state: `qpos = [1.3, 0.5]`, `qvel = [0.0, 0.0]`.
- `N = 2000` integration steps, each one `mujoco.mj_step(model, data)` with no
  external torques/forces (gravity comes from the model).
- After *every* step record the state (the way `simulate.py` records it):

  - `qpos` — `(N, model.nq)` float64 array of joint positions,
  - `qvel` — `(N, model.nv)` float64 array of joint velocities,
  - `t`    — `(N,)` float64 array of the simulation time **after** each step
    (step `i` occurs at time `(i+1)*dt`).

- Final state must be written to `/app/result.npz` as a `np.savez` with keys
  `t`, `qpos`, `qvel` (the same schema `simulate.py` writes). Every recorded
  value must be a finite number (no NaN and no ±Inf).

## Deliverable

Write `/app/optimize.py` (a standalone Python program) and run it so that
`/app/result.npz` exists with the correct contents.  The result file must be
reproducible: running it again must again produce the same bytes.

To prove you measured it, also write `/app/timing.json`:

```json
{
  "slow_seconds": <wall time of simulate.py's slow loop>,
  "optimized_seconds": <wall time of your optimize.py physics loop>,
  "speedup": <slow_seconds / optimized_seconds, >= 4.0>,
  "max_residual": <max abs difference of you state vs a reference>,
  "finite": true
}
```

The physics is fully deterministic: a correct (physics-preserving) fast
implementation reproduces the exact trajectory of the slow baseline.  Measure
the residual and the wall-times yourself; iterate until `max_residual` is tiny
and `speedup` is clearly above 4.  Decide how to profile (e.g. `time`,
`perf_counter`, `time.perf_counter_ns`, `cProfile`, or simply diff a fast
single-compile loop against the per-step recompile of `simulate.py`) before
choosing the final optimization.

Check your work with `python3 -m py_compile /app/optimize.py` and by running it;
then confirm `result.npz` and `timing.json` exist.

## Grading note

`/app/result.npz` gets compared on `qpos` / `qvel` against a reference
free-running simulation of `arm.xml` from identical initial conditions.  Full
credit needs every element within `1e-5` absolute, no NaN/Inf, and the measured
wall-time speedup `>= 2.5` (your optimize.py measured by the harness against a
slow baseline in the same container).  Your own `timing.json` is informational;
the verifier re-measures copies itself.