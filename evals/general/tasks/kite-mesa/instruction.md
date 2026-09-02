# kite-mesa — train a policy for a cold-storage warehouse robot

A fleet of robots moves pallets inside a cold-storage warehouse laid out as an
integer grid with racking walls. You must implement the warehouse environment
and train a policy that drives the robot to the loading dock (a reward disc
around the dock cell) efficiently, then run your trainer to produce a policy
artifact for the shipped warehouse layout.

Everything is CPU-only, small, and fast. **Do not modify any file already in
`/app`.**

## Deliverables (both required)

1. `/app/rl_lab.py` — a module that is simultaneously **runnable as a
   script** and **importable** (the verifier imports it and re-runs it as a
   CLI on hidden warehouse layouts).
2. `/app/policy.json` — produced by running `python3 /app/rl_lab.py` with
   **no arguments** against the shipped `/app/configs/main.json` (see CLI
   contract).

## CLI contract

```
python3 /app/rl_lab.py [--config CONFIG] [--out OUT]
```

- `--config`: warehouse layout JSON (default `/app/configs/main.json`).
- `--out`: where to write the policy artifact (default `/app/policy.json`).

With no arguments it must train on `/app/configs/main.json` and write
`/app/policy.json`. The verifier re-runs the CLI with `--config`/`--out`
pointing at **hidden** layouts.

`policy.json` must be valid JSON with at least:

```json
{"config": "<config path used>", "mean_return": <float>,
 "policy": {"<row>,<col>": <int action 0..3>, ...}}
```

`policy` must contain one entry for **every non-wall cell** of the trained
layout, keyed as `"<row>,<col>"`.

## Environment semantics (exact — the verifier re-checks them)

`GridEnv` is a 2-D integer grid:

- coordinates `(row, col)` in `{0..size-1}`; some cells are **walls**;
- four actions: `0=(−1,0)` up, `1=(+1,0)` down, `2=(0,−1)` left,
  `3=(0,+1)` right — i.e. `deltas = [(-1,0),(1,0),(0,-1),(0,1)]`, applied as
  `row += dr`, `col += dc`;
- rewards are fixed integers: goal reward **+10**, step penalty **−1**,
  wall penalty **−5**;
- a move whose target cell is **outside the grid** bounces off the
  boundary: the position does **not** change and the reward is the step
  penalty (−1);
- a move whose target cell is a **wall** bumps the rack: the position does
  **not** change and the reward is the wall penalty (−5);
- otherwise the robot moves to the target cell and earns **+10** when the
  euclidean distance `sqrt((row−gr)²+(col−gc)²)` to the dock `(gr,gc)` is
  `<= radius` (**inclusive**), else −1;
- `step(action)` returns `(int(reward), (row, col), done)`; `done` is True
  once `horizon` steps have been taken (a bump/bounce counts as a step);
- `reset(pos=None)` places the robot at a random non-wall cell, or at `pos`.

Constructor: `GridEnv(size, walls, goal, radius, horizon)` where `walls` is
any iterable of `(row, col)` wall cells. The layout JSON holds
`{"size", "walls": [[r,c],...], "goal": [gr,gc], "radius", "horizon",
"trials", "threshold", "edge_spec"}`.

## Required importable interface

```python
class GridEnv: ...            # semantics exactly as above
def train_policy(env): ...    # -> callable policy(pos) -> action 0..3
def evaluate_policy(env, policy, trials, horizon): -> float
```

- `train_policy(env)` must return a policy (e.g. via value iteration /
  dynamic programming over the finite horizon) that navigates any start cell
  into the dock disc and keeps collecting the +10 reward there.
- `evaluate_policy(env, policy, trials, horizon)` must return the **mean
  episode return** over `trials` episodes of `horizon` steps. For
  reproducibility it MUST draw start cells with
  `rng = random.Random(20240517)`; the free (non-wall) cells in sorted order
  are `cells`, and each trial starts at `cells[rng.randrange(len(cells))]`.

The verifier, on the shipped layout and on hidden layouts:

1. builds `GridEnv` from the config, calls your `train_policy`, and runs its
   **own** episode simulation through your `env.reset`/`env.step` with the
   same seeded start-cell procedure — the mean return must reach the
   config's `threshold`;
2. calls your `evaluate_policy` with your trained policy and requires it to
   return a finite float;
3. re-checks the environment edge cases listed in the config's `edge_spec`
   (each entry has `"pos"` and `"action"`; the verifier computes the
   expected reward and resulting position from the semantics above and
   compares against your `GridEnv`):
   - a boundary move (out of the grid) stays in place and yields −1;
   - a wall bump stays in place and yields −5;
   - a step landing at euclidean distance exactly `radius` from the dock
     yields +10 (inclusive);
   - a step landing just beyond the radius yields −1.

## Constraints

- Write outputs only under `/app`; do not modify `/app/configs/main.json`.
- CPU-only; the whole train+evaluate run on the shipped layout must finish
  well within a few minutes.
- `numpy` is installed; pure Python is sufficient.
- No network access at verify time.
