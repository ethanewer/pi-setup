# Bin seabird radar fixes into a normalized 2D histogram

The Gull Point radar station records telemetry fixes for seabird tracking. You
must build a reusable command-line program that converts a stream of 2D radar
fixes into a **normalized 2D histogram** over a configurable bounding box and
bin grid, and writes a JSON report. The program must work **on any input** that
follows the documented formats below, not just the shipped files.

## Environment

- Working directory: `/app`. It already contains the input files
  `/app/fixes.txt` (radar fixes) and `/app/grid.txt` (the binning spec).
  Python 3.12 is available as `python3` (standard library only; no numpy
  needed).
- **Do not modify `/app/fixes.txt` or `/app/grid.txt`.**

## Deliverables (both required)

1. `/app/solve.py` — a runnable Python program with this interface:
   ```
   python3 /app/solve.py <fixes_file> <grid_file> <output_json>
   ```
   It must read the fix stream and the grid spec, and write the JSON histogram
   report to the given output path. It must work on any input conforming to the
   contract below.

2. `/app/answer.json` — the report your program produces **when run on the
   provided `/app/fixes.txt` and `/app/grid.txt`**:
   ```
   python3 /app/solve.py /app/fixes.txt /app/grid.txt /app/answer.json
   ```

## Input format

`grid_file` is plain text with exactly two significant lines (blank lines and
surrounding whitespace may appear):

```
box=<xmin>,<xmax>,<ymin>,<ymax>
bins=<nx>,<ny>
```

- `<xmin>,<xmax>,<ymin>,<ymax>` are floats with `xmin < xmax` and
  `ymin < ymax`.
- `<nx>,<ny>` are positive integers: the number of bins along x and y.
- Example: `box=-3.0,5.0,-2.0,2.0` / `bins=4,4` gives a 4x4 grid over
  `[-3,5] x [-2,2]`.

`fixes_file` is newline-separated text. Each non-blank line must be exactly
two comma-separated fields `x,y` where both fields parse as floats (leading or
trailing whitespace inside a field is allowed; scientific notation such as
`1e1` is allowed). Anything else is **malformed**:

- blank lines are ignored entirely (not malformed, not counted);
- lines with one field (`2.5`), three fields (`1,2,3`), non-numeric fields
  (`oops`, `x,y`), empty fields (`7,`), or other separators (`1;2`) are
  malformed.

## Binning rules (must be followed exactly)

A fix `x,y` is **in-box** iff `xmin <= x <= xmax` and `ymin <= y <= ymax`.
Fixes outside the box are excluded from the histogram.

The grid has `nx` columns (x direction) and `ny` rows (y direction), each of
width `wx = (xmax-xmin)/nx` and height `wy = (ymax-ymin)/ny`. An in-box fix
lands in:

- column `min( floor((x - xmin) / wx), nx - 1 )`
- row    `min( floor((y - ymin) / wy), ny - 1 )`

so the leftmost/lowest cell is `[xmin, xmin+wx) x [ymin, ymin+wy)` and the
rightmost/topmost cells are **closed** on their upper edges (a fix exactly on
`xmax` or `ymax` lands in the last column/row; a fix exactly on an interior
edge lands in the higher-index cell).

## Required output JSON

The output file must be valid JSON with exactly these keys:

```json
{
  "box":      [<xmin>, <xmax>, <ymin>, <ymax>],
  "bins":     [<nx>, <ny>],
  "histogram": [[<float>, ...], ...],
  "outside":  <int>,
  "malformed": <int>,
  "binned":   <int>
}
```

- `histogram` has exactly `ny` rows and `nx` columns per row. Row 0 is the
  lowest y-band, column 0 is the leftmost x-band. `histogram[row][col]` =
  (number of in-box fixes in that cell) / (total number of in-box fixes).
  Entries are floats and **sum to 1.0** whenever at least one fix is in-box.
- If zero fixes are in-box (including an empty fixes file), every histogram
  entry is `0.0` and `binned` is `0`.
- `outside` = number of well-formed fixes that fall outside the box.
- `malformed` = number of non-blank lines that do not parse as two floats.
- `binned` = number of in-box fixes (the denominator of the normalization).

## Edge cases the grader's hidden inputs probe

- Fixes exactly on interior bin edges and on the box corners/edges (must land
  in the higher-index or last cell per the rule above).
- Fixes just outside the box (e.g. `xmax + 0.0001`) — excluded, counted in
  `outside`.
- Scientific-notation coordinates (`1e1`, `2.5e0`).
- Fractional normalized entries (e.g. 1 fix among 8 → `0.125`; among 3 →
  `0.333...`).
- Malformed and blank lines interleaved anywhere.
- A `bins=1,1` grid: every in-box fix lands in the single cell, which must be
  exactly `1.0`.
- An empty fixes file: all-zero histogram of the right shape, `binned` 0,
  `outside` 0, `malformed` 0.
- Negative coordinates.

## Constraints

- The verifier runs your program **unchanged** (`python3 /app/solve.py`) on
  hidden inputs in the same formats, so do not hard-code the provided file
  contents or filenames.
- No network access at verify time; Python standard library only.
- Do not modify `/app/fixes.txt` or `/app/grid.txt`.
