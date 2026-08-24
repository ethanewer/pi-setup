# Optimize a MuJoCo simulation that has a latent NaN bug (item-073, hard)

`/app/arm.xml` is a gravity-driven **double pendulum** MJCF model (two revolute
joints, no actuators, deterministic dynamics). `/app/simulate.py` is a starting
point that simulates it but is **broken twice over**:

1. it is slow — it recompiles the whole MJCF model from the XML string on
   **every** step, and shovels every sample through nested Python lists;
2. it is numerically dirty — while recording, it "cleans" each velocity sample
   by dividing it by the current second-joint velocity.  A real double
   pendulum's joint velocity crosses zero many times, so this division
   produces **±Inf and NaN** on some rows, and the garbage then contaminates
   every later row.

Run it once and inspect `/app/result.npz`: you will find non-finite values.
That is the regression you must eliminate while keeping the **exact same
physics**.

## Your task

Write `/app/optimize.py` that simulates the same model from the same initial
state for the same number of steps, records the **raw** physical state (no
normalization, no post-processing), runs at least **4x faster** than
`/app/simulate.py` (wall time, measured in this container), and produces
**only finite numbers** on every row.

## Fixed contract (do not deviate)

- Model: `/app/arm.xml`, timestep `dt` from the model.
- Initial state: `qpos = [1.3, 0.5]`, `qvel = [0.0, 0.0]`.
- `N = 3000` integration steps, each `mujoco.mj_step(model, data)`, gravity
  from the model, no actuators/control.
- Record **after every step** and write `/app/result.npz` with `np.savez`
  arrays:
  - `qpos` — `(N, model.nq)` float64 — joint positions after each step,
  - `qvel` — `(N, model.nv)` float64 — joint velocities after each step,
  - `t` — `(N,)` float64 — simulation time after each step (`(i+1)*dt`).
- Every element of `qpos`, `qvel`, `t` must be finite.

## Verification procedure (do it yourself, in stages)

1. **Profile**: time `/app/simulate.py` (that gives you your `slow_seconds`
   baseline).  Profile where the time goes (e.g. `time.perf_counter`,
   `cProfile`) so you know what to hoist out of the loop.
2. **Inspect the state**: load `/app/result.npz` and check for NaN/Inf.  Find
   the exact rows where the normalization explodes and confirm *why*.
3. **Rebuild the correct pipeline**: compile the model once, step one
   `MjData` N times, record raw `qpos`/`qvel`.  This is both the fix and the
   optimization.
4. **Measure state residuals**: your raw recording must equal the unoptimized
   continuous integration of the same model (identical physics).  Since the
   physics is deterministic, a correct implementation reproduces the reference
   trajectory to near machine precision.  Compute the max absolute residual of
   `qpos` and `qvel` against such a reference run and confirm it is below
   `1e-6`.
5. **Avoid NaN/Inf regressions**: assert `np.isfinite(...)` on your final
   arrays, and re-run your solution twice to make sure the output is stable
   (bit-identical).
6. Write `/app/timing.json` with your measurements:

```json
{
  "slow_seconds": <float>,
  "optimized_seconds": <float>,
  "speedup": <float>,
  "max_residual": <float>,
  "finite": true
}
```

`optimized_seconds` is the wall time of your `/app/optimize.py` physics loop;
`speedup = slow_seconds / optimized_seconds` must be >= 4.0.

## Grading

The verifier re-derives the reference free-run itself and compares your
`/app/result.npz` on `qpos`/`qvel` (max abs residual <= `1e-6`), checks that
all values are finite, and measures your `optimize.py` wall time against a
per-step recompiling baseline in the same container.  Full credit: residual
pass, finite, speedup >= 4.0.  Partial credit (0.5): physics and finiteness
correct but speedup < 4.0.  Your `timing.json` is informational; the verifier
re-measures independently.

Work in stages and iterate.  Do not modify `arm.xml`, `simulate.py`, or the
`mujoco` install; the final deliverable is `/app/optimize.py` +
`/app/result.npz` + `/app/timing.json`.