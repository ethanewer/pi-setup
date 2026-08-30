# Basalt-dial — tune the mission replay propagator

**Basalt-dial** mission control replays tracked two-body orbits with a fixed
propagator engine. The engine supports several numerical schemes and optional
perturbations, exposed as a tuning configuration. Your job: **select the
tuning knobs** so that, under a hard budget of right-hand-side (acceleration)
evaluations, the engine's final state reproduces the **calibrated reference
model** to within a tight absolute tolerance on **every** replay case —
including randomized ones you have not seen. A configuration that changes the
physics, is too coarse, exceeds the budget, or produces NaN/Inf is a failed
run.

Everything lives in `/app`:

- `/app/engine.py` — the fixed propagator engine (do **not** modify it).
- `/app/data/case_visible.json` — a visible replay case (do **not** modify).

`python3` is available (standard library only; no numpy, no network).

## The engine

```
python3 /app/engine.py simulate  <case.json> <config.json> <out.json>
python3 /app/engine.py reference <case.json> <out.json>
```

- `simulate` integrates the case with the scheme/knobs in `<config.json>`.
- `reference` integrates the same case with the **calibrated reference model**
  (fixed high-order scheme, fine fixed step, no perturbations, no budget).
  Use it locally to measure how close a candidate configuration gets.
- On a malformed case or config the engine prints `ERR: ...` to stderr and
  exits non-zero (it never writes an output file in that situation).

### Case format (`case.json`)

```json
{"name": "visible", "mu": 1.0, "state0": [x, y, vx, vy], "T": 3.7,
 "budget": 3000, "tol": 1e-06}
```

`state0` is the initial state; the engine integrates the two-body problem
(`mu` gravitational parameter) over `[0, T]`. `budget` is the hard ceiling on
acceleration evaluations for `simulate`; `tol` is the required absolute
tolerance on the final state.

### Config format (`config.json`) — all six keys required, exactly these

```json
{
  "method": "rk4",
  "steps": 400,
  "enable_drag": false,
  "drag_coeff": 0.0,
  "softening": 0.0,
  "renormalize": false
}
```

- `method`: `"euler"`, `"heun"`, or `"rk4"` (costs 1 / 2 / 4 acceleration
  evaluations per step respectively).
- `steps`: integer in `[1, 100000]` — number of uniform integration steps.
- `enable_drag`: boolean; when true a velocity drag `-drag_coeff * v` is added
  to the dynamics (this **changes the physics**).
- `drag_coeff`: finite number in `[0, 10]` (only active with drag on).
- `softening`: finite number `>= 0` (used as a Plummer-style `+softening`
  on `r²`; any non-zero value **changes the physics**).
- `renormalize`: boolean; when true the velocity is rescaled after every step
  to exactly conserve the initial energy (this also **changes the physics**
  relative to the plain model).

`simulate` output JSON: `{"case", "status", "nfev", "final", "method",
"steps"}` where `status` is `"ok"` only when the run completed within the
budget with finite results; otherwise `"budget-exceeded"` (or `"diverged"`)
and `final` is `null`.

## Deliverables (both required)

1. **`/app/config/tuning.json`** — your selected configuration, in the exact
   six-key schema above.

2. **`/app/tuning_report.json`** — the `simulate` output your configuration
   produces on the visible case:
   ```
   python3 /app/engine.py simulate /app/data/case_visible.json \
     /app/config/tuning.json /app/tuning_report.json
   ```
   Keep the file in place after generating it.

## What the verifier requires

The verifier re-runs `simulate` with **your** `/app/config/tuning.json` on the
visible case and on several **hidden** cases with randomized initial states
drawn from these documented ranges:

- perigee radius `rp ∈ [0.55, 1.0]`, eccentricity `e ∈ [0.1, 0.7]`
  (start at perigee, purely tangential velocity, `mu = 1.0`),
- horizon `T ∈ [2.0, 5.0]`,
- `budget = 3000`, `tol = 1e-06`.

For every case, all of the following must hold:

- the config is schema-valid (the engine must exit 0, not `ERR:`);
- `status` is `"ok"` and `nfev <= budget`;
- `final` is present and all four components are finite (no NaN/Inf);
- every component of `final` is within `tol` of the `reference` mode's final
  state for that case (max absolute componentwise difference `<= tol`).

The verifier also re-runs the exact command from Deliverable 2 and requires
`/app/tuning_report.json` to equal the fresh output of your configuration on
the visible case, and that `/app/engine.py` and `/app/data/case_visible.json`
are unmodified.

### Tuning hints (the failure modes to avoid)

- `euler` even with the maximum affordable step count is far too coarse for
  the eccentric hidden cases.
- `heun` at its maximum affordable step count still misses the tolerance.
- `rk4` is accurate enough, but only with a sufficiently fine step count —
  too few steps drift past `tol` on the faster (small-perigee) orbits.
- More steps cost proportionally more evaluations: `4 × steps` must stay
  `<= budget`.
- Any perturbation knob (`enable_drag`, non-zero `softening`,
  `renormalize`) departs from the plain reference dynamics and will blow
  past `tol` on at least some hidden cases.

## Constraints

- Deterministic; no randomness of your own is needed; no network; standard
  library only.
- Do not modify `/app/engine.py` or anything under `/app/data`.
- Do not hard-code to the visible case — the same configuration must work on
  every hidden case in the documented ranges.
