# Frost Link — parametric spacer/flange geometry engine

Implement a small **parametric mechanical-part geometry engine** in pure
Python (math only, no CAD libraries). It models a family of annular spacer
flanges: a circular flange disk with a central bore and `bolt_count` bolt
holes drilled on a bolt circle. The engine computes geometry values, checks a
part spec against design rules, and emits a JSON report.

## Environment

- Container `bench-base:python-3.12`; Python 3.12 **stdlib only** (`math`,
  `json`). No network, no extra packages.
- Everything is deterministic CPU math: no randomness, no clocks.

## The spec

A part spec is a JSON object / Python dict with exactly these seven keys:

| key             | meaning                                  | unit    |
|-----------------|------------------------------------------|---------|
| `bore_d`        | central bore diameter (axis at origin)   | mm      |
| `flange_d`      | outer flange diameter                    | mm      |
| `thickness`     | axial thickness                          | mm      |
| `bolt_count`    | number of bolt holes (positive integer)  | —       |
| `bolt_circle_d` | diameter of the bolt circle              | mm      |
| `bolt_hole_d`   | diameter of each bolt hole               | mm      |
| `density`       | material density                         | g/cm³   |

The visible fixture is **`/app/specs/spacer_spec.json`** (the seven fields
above; this part is valid under the default limits). Treat `/app/specs/` as
read-only.

## Deliverables

1. **`/app/cadmodel.py`** — an importable module exposing the documented
   functions below.
2. **`/app/spacer_report.json`** — the report (schema below) for the visible
   fixture, computed with the **default limits**
   `{"min_wall_margin": 2.0, "min_hole_gap": 1.5, "min_bore_gap": 2.5}`.

## Geometry conventions (exact — implement literally)

Let `b = bolt_count` and `r = bolt_circle_d/2`.

- `bolt_hole_centers(spec)` → list of `b` `(x, y)` tuples. Hole `i`
  (`0 <= i < b`) sits at angle `a = 2*pi*i/b` measured counter-clockwise from
  the +X axis (the bore axis is the origin), centered at
  `(r*cos(a), r*sin(a))`; hole 0 is therefore at `(r, 0.0)`. Return
  full-precision floats.
- `min_edge_clearance(spec)` → float mm (may be negative), the minimum of:
  1. for each adjacent pair `(i, (i+1) % b)` — only when `b >= 2` — the
     Euclidean distance between the two hole centers minus `bolt_hole_d`;
  2. bore edge: `r - bore_d/2 - bolt_hole_d/2`;
  3. flange edge: `flange_d/2 - r - bolt_hole_d/2`.
- `annular_area(spec)` → mm², exactly
  `(math.pi/4) * (flange_d**2 - bore_d**2 - bolt_count * bolt_hole_d**2)`.
  **Overlap convention:** every bolt hole is subtracted at its full nominal
  circle even where it overlaps the bore or a neighbouring hole; nothing is
  clipped to the flange; no union/overlap correction.
- `solid_volume(spec)` → mm³, exactly `thickness * annular_area(spec)`.
  **Overlap convention:** bolt holes are straight through-holes spanning the
  full thickness, subtracted in full; no overlap correction.
- `mass_grams(spec)` → g, exactly `solid_volume(spec) * density / 1000.0`
  (density is g/cm³, volume is mm³, `1 cm³ = 1000 mm³`).
- The geometry functions raise `ValueError` when a numeric key is absent or
  not a finite positive real, or `bolt_count` is not a positive `int`
  (`bool` counts as invalid) — they require a well-formed numeric spec.

## `validate_spec(spec, limits)` → list of violation codes

`limits` must be a dict with the required keys `min_wall_margin`,
`min_hole_gap`, `min_bore_gap` (non-negative finite reals; extra keys are
ignored; a missing or invalid key raises `ValueError`).

Field-level codes, for the numeric keys `bore_d`, `flange_d`, `thickness`,
`bolt_circle_d`, `bolt_hole_d`, `density` (a value is numeric iff it is an
`int`/`float`, not a `bool`, and finite):

- `INVALID_<FIELD>` — key missing or value non-numeric (string, bool, NaN,
  ±inf), `<FIELD>` ∈ {`BORE_D`, `FLANGE_D`, `THICKNESS`, `BOLT_CIRCLE_D`,
  `BOLT_HOLE_D`, `DENSITY`}.
- `NONPOSITIVE_<FIELD>` — numeric but `<= 0`.
- `BOLT_COUNT_INVALID` — `bolt_count` missing, not an `int`, a `bool`, or
  `< 1`.

Geometry codes are evaluated **only when every numeric field is a finite
positive real and `bolt_count` is a positive `int`**:

- `BORE_NOT_INSIDE_BOLT_CIRCLE` — `bolt_circle_d <= bore_d` (the bolt circle
  must lie strictly outside the bore).
- `HOLE_OUTSIDE_FLANGE` — `bolt_circle_d + bolt_hole_d > flange_d` (a hole
  rim crosses the outer edge; touching exactly is allowed).
- `HOLE_TOO_CLOSE_TO_BORE` — `(bolt_circle_d - bore_d - bolt_hole_d)/2 <
  min_bore_gap`.
- `HOLE_TOO_CLOSE_TO_FLANGE_EDGE` — `(flange_d - bolt_circle_d -
  bolt_hole_d)/2 < min_wall_margin`.
- `ADJACENT_HOLES_TOO_CLOSE` — `b >= 2` and for some adjacent pair
  `(i, (i+1) % b)`, center distance − `bolt_hole_d` < `min_hole_gap`.

All comparisons use the **unrounded** float values (equality passes). The
return value is the **alphabetically sorted, deduplicated** list of codes
(Python `sorted()`).

## Report schema (`spacer_report.json`)

The module also exposes `build_report(spec, limits) -> dict` with this exact
schema; every numeric value is rounded with Python's `round(x, 4)`:

```json
{
  "spec": { ...seven fields echoed verbatim, numbers as parsed... },
  "limits": {"min_wall_margin": ..., "min_hole_gap": ..., "min_bore_gap": ...},
  "bolt_hole_centers": [[x, y], ...],
  "min_edge_clearance_mm": <rounded>,
  "annular_area_mm2": <rounded>,
  "solid_volume_mm3": <rounded>,
  "mass_g": <rounded>,
  "violations": [<sorted codes>],
  "valid": <true iff violations empty>
}
```

- `spec` and `limits` are echoed **without** rounding.
- `bolt_hole_centers` entry `i` is `[round(x, 4), round(y, 4)]`.
- `build_report` has the same well-formedness precondition as the geometry
  functions (`ValueError` on a malformed spec). The visible fixture is
  well-formed and valid, so its `violations` is empty and `valid` is `true`.
- Serialize with `json.dumps` (any indent is fine).

## How the grader probes it

- Imports **`/app/cadmodel.py`** and re-runs every documented function on the
  visible spec and on hidden specs (other bolt counts including 1 and large
  counts, tiny margins, planted violations, malformed field values),
  comparing each result against an independent recompute from the
  conventions above.
- Checks **`/app/spacer_report.json`** against the verifier's own recompute
  of `/app/specs/spacer_spec.json` (parsed-JSON comparison).
- Calls `validate_spec` and `build_report` with several different `limits`
  dicts, so hardcoding a single report or ignoring the `limits` argument
  fails.

## Constraints

- Python 3.12 stdlib only; no network; deterministic; write only under
  `/app` (plus `/tmp` scratch). Do not modify `/app/specs/`.