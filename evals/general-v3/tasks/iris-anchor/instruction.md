# iris-anchor — robotics sensing bundle

A warehouse robot needs three things set up: a **path plan** that obeys
elevation and stackable-block rules, a **board-state read** from a camera image,
and a **faster MuJoCo model** that still reproduces the reference physics. You
must build three reusable deliverables under `/app` and produce their outputs
for the shipped fixtures.

Environment packages available (do not require anything else): `numpy`,
`mujoco`, `opencv-python-headless`, `pillow`.

---

## Deliverables

| path | what |
|------|------|
| `/app/planner.py` | reusable block path planner |
| `/app/decode_board.py` | reusable image -> board JSON decoder |
| `/app/path.json` | output of the planner on `/app/grid.json` |
| `/app/board.json` | output of the decoder on `/app/board.png` |
| `/app/tuned.xml` | tuned MuJoCo model (see *Part 3*) |

Do **not** modify `/app/grid.json`, `/app/board.png`, or `/app/reference.xml` —
those are the shipped fixtures. Every deliverable program must accept its input
as a command-line argument and work on **any** input with the same format,
including unseen ones the grader will supply.

---

## Part 1 — block path planner (`/app/planner.py`)

A robot moves on a `rows` x `cols` grid. It starts at a cell carrying some
blocks and must reach a goal cell. Each cell has an integer **base elevation**
(`0..4`) and every cell may have a stack of **added blocks** on top of it.

Interface:

```
python3 planner.py <grid.json> -o <out.json>
```

`<out.json>` must be:

```
{"actions": [ {"type":"move","to":[r,c]},
              {"type":"place","at":[r,c]},
              {"type":"pick","at":[r,c]} , .. ], "reaches": true}
```

`reaches` is `true` iff the action sequence takes the robot from start to goal
under the rules below. The `to`/`at` fields are `[row, col]` coordinates.

### Input format (`<grid.json>`)

```json
{
  "rows": 7, "cols": 7,
  "base": [[row-major ints, ...]],
  "blocked": [[false, ...], ...],       // true cells are impassable, never enter
  "start": [r, c],
  "goal": [r, c],
  "capacity": 3,          // max blocks carried at once
  "max_stack": 2,         // max blocks stacked on a single cell
  "start_carry": 3        // blocks the robot holds at the start
}
```

### Movement rules (single-step, cost 1 each)

- **move** to an orthogonally adjacent, in-bounds, non-blocked cell `(nr,nc)`: allowed iff
  `elevation(nr,nc) <= elevation(r,c) + 1`. Climbing **up by more than 1 per move is
  disallowed**; descending any amount is always allowed.
- **place** a block at a cell adjacent (side-neighbor) **or equal to** the robot's current
  cell. Requires `carry > 0` and that cell's stack `< max_stack`. Elevation of that cell `+1`, `carry - 1`.
- **pick** a block up from a cell adjacent **or equal to** the current cell. Requires
  that cell has at least one stacked block and `carry < capacity`. Elevation of that cell `-1`, `carry + 1`.

`elevation(r,c) = base[r][c] + (number of blocks stacked there)`.

Blocks are conserved: the stack on every cell plus `carry` is always `start_carry`.
A cell's stack never exceeds `max_stack`, and `carry` never exceeds `capacity`.
The robot may stack blocks under its own cell to climb tall cliffs.

The grader re-runs your planner on **unseen** grids (including grids `up to 9x9`,
different elevations, different capacities / stack limits, and some `blocked`
cells) and requires a valid `reaches: true` action list each time.

---

## Part 2 — board decoder (`/app/decode_board.py`)

A board camera produced a PNG of a board with **9 x 9 intersections** (8 cells
per side). Black and white **stones** are solid disks centered on intersections;
empty intersections show the light wooden background.

Interface:

```
python3 decode_board.py <image.png> -o <out.json>
```

`<out.json>` must be:

```
{"n": 9, "stones": [ {"r": r, "c": c, "color": "black"}, ... ]}
```

`r`,`c` are intersection row/column in `0..8`; `color` is `"black"` or `"white"`.
The list must contain **exactly** the occupied intersections, and no empties.

### Board geometry (fixed for this task)

- Image is square; `n = 9` intersections per side.
- Intersection `(i, j)` is centred at pixel `(48 + j*48, 48 + i*48)`.
- Stones are disks of radius `17` px centered on their intersection.
- Grid lines are `3` px wide, so a thin `+` line-cross appears at an empty intersection.
- Render palette (RGB): background wooden `(242, 220, 215)`, grid lines `(70,70,70)`,
  black stones `(15,15,15)`, white stones `(245,245,245)` with a dark `(40,40,40)` border.

Distinguish a stone from an empty crossing by sampling the annulus around each
intersection centre offset from the exact cross location (e.g. include pixels at
radius `6..13` from centre). Black `(15,15,15)` and white `(245,245,245)` sit far
from the wooden background, so classify by which of the three reference colours
the sampled mean is nearest.

The grader re-runs your decoder on **unseen** board images (same geometry, colours)
and requires an exact match of the occupied-cell set and ownership.

---

## Part 3 — MuJoCo tuning (`/app/tuned.xml`)

`/app/reference.xml` is a passive rigid **double-link pendulum** (two hinge joints,
`th1`/`th2`) released from rest. `reference.xml` uses `timestep="0.0005"` with the
`RK4` integrator. Read it, then produce a new model file `/app/tuned.xml` that
**simulates the same scene faster while preserving the physics trajectory**.

The grader measures both models in the same way:

- simulates `4.0 s` from joint rest at `qpos = [1.2, -0.9]` (rad) under gravity,
  no actuation / no contacts;
- samples the joint positions every `0.02 s` (so the sampled joint trajectory must
  stay aligned with a sampling grid of period `0.02 s`);
- computes the median wall-clock time over repeated runs.

Acceptance: your `/app/tuned.xml` must satisfy **both**

1. **speed** — the tuned model's median sim wall time ≤ `60%` of the reference
   model's median wall time;
2. **fidelity** — at every one of the 200 sample instants, `|qpos_tuned - qpos_ref|`
   stays below `0.06` rad for both joints.

You are free to tune `timestep`, `integrator`, solver options, and iterations.
Constraint: because the life sampled trajectory must align with the 0.02 sampling
grid, choose a `timestep` (seconds) that divides `0.02` exactly (e.g. `0.0005`,
`0.001`, `0.002`, `0.004`, `0.005`, `0.01`). Do **not** change the model topology
(bodies, geoms, joints, initial layout); the grader checks the tuned model exposes
the same 2 degrees of freedom and reproduces the reference trajectory within the
tolerance.

Hints: a larger aligned timestep integrators fewer steps per second of sim-time,
so a model that simply bumps `timestep` (keeping `RK4`) simulates proportionally
faster while the physics state stays practically identical over the smooth
passive dynamics — tune it and measure.

---

## Submission checklist

- `planner.py` general and reads `<grid.json>` from the command line.
- `decode_board.py` general and reads `<image.png>` from the command line.
- `/app/path.json`, `/app/board.json`, `/app/tuned.xml` all present and correct.
- Everything must work from a pristine `/app` after only your deliverables land here,
  without network, GPU, or root/system services.