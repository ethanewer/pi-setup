# Marlin-rig — feature matching + robust geometric model fit

You are building the correspondence QA tool for **Marlin-rig**, a
photogrammetry rig. Two views of a textured calibration plate are shipped as
intensity rasters plus candidate keypoint lists. Your job: **match features
between the views** and **robustly fit a 2-D similarity transform** to the
correspondences with an exact, deterministic RANSAC-style procedure — and to
fail *softly* (report a degenerate run) instead of crashing when no consistent
model exists. Everything is pure standard-library Python; there is **no numpy
and no network**.

## Environment

- Working directory `/app`. The shipped fixture is the scenario directory
  `/app/data/scenario` (five files, see below).
- **Do not modify or move anything under `/app/data`.**

## Scenario directory layout (identical for every scenario, visible or hidden)

| file               | content                                                             |
|--------------------|---------------------------------------------------------------------|
| `scenario.json`    | `{"name": <string>, "tau": <number>}` — scenario id and inlier tolerance `tau` |
| `view_a.txt`       | first line `W H`, then `H` lines of `W` integers (0..255), space-separated |
| `view_b.txt`       | same format for the second view                                     |
| `keypoints_a.json` | JSON list of `[x, y]` integer keypoints in view A                   |
| `keypoints_b.json` | JSON list of `[x, y]` integer keypoints in view B                   |

## Deliverables (both required)

1. **`/app/fit.py`** — a runnable program:
   ```
   python3 /app/fit.py <scenario_dir> <out.json>
   ```
   It reads the scenario directory and writes the result JSON to `<out.json>`.
   It must work on **any** scenario directory with this layout (the verifier
   re-runs it on hidden scenarios), and it must **never crash** — a scenario
   with no consistent model produces a `"degenerate"` result (below), not an
   exception.

2. **`/app/fit_result.json`** — the result your program produces on the
   shipped visible scenario:
   ```
   python3 /app/fit.py /app/data/scenario /app/fit_result.json
   ```

## 1. Descriptors

Patch half-width is `h = 2` (a 5×5 patch). For each keypoint `(x0, y0)` of a
view, in file order:

- If the full window `x0-2 .. x0+2`, `y0-2 .. y0+2` is not entirely inside the
  raster, the keypoint is **skipped**.
- Build the 25-value patch in **row-major** order (rows `y0-2..y0+2`, within a
  row columns `x0-2..x0+2`), as floats.
- Center it: subtract the mean of the 25 values. If the L2 norm of the
  centered vector is `< 1e-12` (e.g. a constant patch), the keypoint is
  **skipped**.
- Otherwise normalize by that L2 norm. This unit vector is the descriptor.

The kept keypoints retain their relative file order; their descriptor-list
indices (`0, 1, 2, ...` over kept keypoints only) are what the output refers
to. Count skipped keypoints per view.

## 2. Matching (deterministic)

Distances are **squared** L2 between unit descriptors.

For each descriptor `a` in view A (in kept order):

- Compute `d(j) = ||a - b_j||²` for every kept descriptor `b_j` of view B.
- `best_j` = index of the minimum (ties → **lowest** `j`).
- `second` = the second-smallest distance over a **different** index than
  `best_j`.
- Accept `a -> best_j` iff `best <= 0.8 * second` (when view B has only one
  kept descriptor, accept unconditionally).
- **Mutual check**: precompute, for each B descriptor `j`, `argmin_i ||a_i -
  b_j||²` over A (ties → lowest `i`). Keep the pair only if that argmin for
  `best_j` is exactly `a`'s index.

The match list is in A order; each match is a pair `(i, j)` of kept-descriptor
indices.

## 3. Robust similarity fit (exact, deterministic — no randomness)

Each match `(i, j)` is a correspondence from source point `p = (x, y)` (the A
keypoint) to target point `q = (u, v)` (the B keypoint). The model is the 2-D
similarity transform `M(p) = (a·x − b·y + tx,  b·x + a·y + ty)`.

**Residual** of a match under `(a, b, tx, ty)` =
`hypot(M(p).x − q.x, M(p).y − q.y)`.

### 3a. Exhaustive minimal-sample search

Enumerate **all unordered pairs of matches** `(i, j)` with `i < j`, in
lexicographic order `(i, j)`. For each pair with source points `p1, p2`:

- Let `dx = p2.x - p1.x`, `dy = p2.y - p1.y`, `den = dx² + dy²`. If
  `hypot(dx, dy) < 1e-9`, skip the pair.
- Exact model through the two correspondences (complex division
  `(q2−q1)/(p2−p1)`):
  ```
  a  = ((q2.x − q1.x)·dx + (q2.y − q1.y)·dy) / den
  b  = ((q2.y − q1.y)·dx − (q2.x − q1.x)·dy) / den
  tx = q1.x − (a·p1.x − b·p1.y)
  ty = q1.y − (b·p1.x + a·p1.y)
  ```
- Inlier set = all matches with residual `<= tau`.
- Track the best candidate: **largest inlier count**, ties → **smallest sum of
  inlier residuals**, ties → the first `(i, j)` in enumeration order.

If no valid pair exists, or the best inlier count is `< 3`, the run is
**degenerate**.

### 3b. Iterative least-squares refinement

Start from the best model's inlier set, then repeat at most 10 times:

1. Fit the least-squares similarity to the current inlier correspondences
   (closed form; with centered coordinates `x' = x−mx, y' = y−my, u' = u−mu,
   v' = v−mv`, `S = Σ(x'² + y'²)`):
   - If `S < 1e-9`: `a = 1, b = 0, tx = mu − mx, ty = mv − my`.
   - Else:
     ```
     a  = Σ(x'·u' + y'·v') / S
     b  = Σ(x'·v' − y'·u') / S
     tx = mu − (a·mx − b·my)
     ty = mv − (b·mx + a·my)
     ```
2. Recompute the inlier set with the new parameters.
3. If the inlier set is unchanged, **stop** (keep the new parameters).
   Otherwise adopt the new inlier set and parameters; if the new inlier count
   dropped below 3, the run is **degenerate**.

After the loop, if the final inlier count is `< 3`, the run is **degenerate**.

## 4. Output JSON (exact keys)

```json
{
  "scenario": "<scenario.json name>",
  "tau": 3.0,
  "n_keypoints_a": 100,
  "n_keypoints_b": 100,
  "n_skipped_a": 0,
  "n_skipped_b": 0,
  "n_matches": 44,
  "matches": [[0, 3], [1, 7]],
  "status": "ok",
  "params": {"scale": 1.25, "theta": 0.15, "tx": 8.7, "ty": 5.2},
  "inliers": [0, 2, 5],
  "n_inliers": 3,
  "rms_inlier": 0.41,
  "residuals": [0.1, 12.3, 0.2]
}
```

- `params` = `{"scale": hypot(a, b), "theta": atan2(b, a), "tx": ..., "ty": ...}`.
- `inliers` = sorted list of match indices (ascending, which is how the loop
  produces them); `n_inliers` = its length.
- `rms_inlier` = `sqrt(mean of squared residuals over inliers)`.
- `residuals` = residual of **every** match, in match order.
- On a **degenerate** run: `"status": "degenerate"`, `params` = `null`,
  `inliers` = `[]`, `n_inliers` = `0`, `rms_inlier` = `null`,
  `residuals` = `null`. Everything else (counts, `matches`, `tau`) is still
  filled in. The program still exits 0.

## 5. Hidden probing

The verifier re-runs `/app/fit.py` on hidden scenarios with different raster
sizes, textures, tolerances, and keypoint sets, including:

- heavy outlier contamination (many false keypoints/matches) — the robust fit
  must still recover the consensus model;
- a scenario with **no consistent transform** — the correct result is a
  `"degenerate"` report, not a crash or a bogus fit;
- duplicate/identical patches (exact distance **ties** — tie-breaks matter)
  and constant patches (zero-norm descriptors that must be skipped);
- a minimal scenario with exactly the minimum number of correspondences.

Float outputs are compared with a small tolerance, but the discrete outputs
(`matches`, `inliers`, counts, `status`, skipped counts) must match exactly —
so follow the deterministic tie-break rules precisely.

## Constraints

- Deterministic; no randomness, no network, standard library only.
- Do not hard-code the visible scenario's numbers or paths beyond the CLI
  contract.
