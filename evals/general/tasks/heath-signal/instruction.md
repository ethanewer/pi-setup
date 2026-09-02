# Heath Signal — normalize an acoustic point cloud into a 2D histogram

The heathland acoustic-survey team records echo points as flat CSV files. You
must build a reusable command-line program that bins a 2D point cloud into a
normalized 2D histogram over a given bounding box, and then RUN it on the
shipped fixture so the answer file exists.

## Environment

- Working directory: `/app`. It already contains the visible fixture files
  `/app/points.csv` and `/app/spec.json`. Python 3.12 (standard library only)
  is available as `python3`.
- **Do not modify `/app/points.csv` or `/app/spec.json`.**

## Deliverables (both required)

1. `/app/gridder.py` — a runnable Python program with this interface:
   ```
   python3 /app/gridder.py <points_csv> <spec_json> <output_json>
   ```
   It must read a point cloud and a binning spec and write the histogram
   summary to the given output path. It must work on **any** input conforming
   to the formats below — the grader runs it unchanged on hidden inputs.

2. `/app/answer.json` — the output your program produces **when run on the
   provided visible fixture**:
   ```
   python3 /app/gridder.py /app/points.csv /app/spec.json /app/answer.json
   ```

## Input formats

`points_csv` is plain text. Each non-empty line that is not a comment holds
exactly two comma-separated decimal numbers `x,y` (whitespace around fields is
allowed and must be stripped). Lines whose first non-whitespace character is
`#` are comments and must be ignored, as are blank lines. There is no header
row. Coordinates may be negative and non-integer.

`spec_json` is a JSON object:
```json
{ "box": [xmin, xmax, ymin, ymax], "bins": [nx, ny] }
```
`nx` is the number of bins along x, `ny` the number of bins along y. Both are
positive integers. The box bounds are decimals; `xmin < xmax` and
`ymin < ymax` always hold.

## Binning contract (probed by hidden inputs — implement exactly)

- A point counts toward the grid only if `xmin <= x <= xmax AND
  ymin <= y <= ymax`. Both **maximum edges are inclusive**: a point exactly on
  `xmax` or `ymax` falls into the last bin of its axis.
- Bin width along x is `wx = (xmax - xmin) / nx`; the column index of an
  in-box point is `int((x - xmin) / wx)`, clamped so a point on `xmax` lands
  in column `nx - 1`. Rows work the same way along y with `wy` and `ny`.
- Row `i` of the grid covers the **i-th y band from the bottom** (row 0 is the
  lowest y band); column `j` covers the j-th x band from the left. So
  `grid[i][j]` uses y for rows and x for columns.
- Each cell holds the **fraction of in-box points** in that cell: divide the
  raw count by the number of in-box points `M`. The grid therefore **sums to
  exactly 1.0** whenever `M > 0`.
- If **no** point is in the box, the grid is all zeros of shape `(ny, nx)`
  (its sum is `0.0`; that empty case is legal and tested).

## Required output JSON

The output file must be valid JSON with exactly these keys:
```json
{
  "shape": [ny, nx],
  "grid": [[...], ...],
  "total_points": <int>,   // all points parsed from the file (comments/blanks excluded)
  "in_box": <int>,         // points inside the closed box (M)
  "grid_sum": <float>      // sum of all grid cells (1.0, or 0.0 when M == 0)
}
```
`grid` has `ny` rows, each with `nx` floats. `total_points` counts every
parsed data line, including out-of-box points.

## Edge cases the grader probes on hidden inputs

- Comments, blank lines, and whitespace-padded fields in the CSV.
- Negative coordinates and non-integer coordinates.
- Points exactly on any of the four box edges (all count; on-max-edge points
  land in the last bin of that axis).
- Points outside the box on either side — excluded from the grid **and** from
  the denominator `M`.
- `nx` or `ny` equal to 1 (single-band axis).
- The empty case: every point out of the box → zero grid, `in_box: 0`,
  `grid_sum: 0.0`.

## Constraints

- The verifier runs `/app/gridder.py` unchanged on hidden inputs, so do not
  hard-code the visible fixture's contents or filenames.
- Standard library only; no network access.
- Do not modify `/app/points.csv` or `/app/spec.json`.
