# juniper-bridge — heritage archive restoration

A civil-engineering archive was scanned. The scans were stored as images and
plotter tool-path logs, and a number of derived facts must be recovered from
them. You must write **one reusable program** that, given a scenario directory,
recovers every requested datum and emits the deliverables described below.

## Deliverable

Write an executable program at `/app/solve.py`:

```
python3 /app/solve.py <input_dir> <output_dir>
```

- `<input_dir>` is a scenario directory (see *Input layout*). Your program must
  accept it on the command line; it may **not** assume a fixed path, and it may
  not hard-code any file paths to the shipped fixture.
- `<output_dir>` is where you write your deliverables. Create it if needed.
- The program must work on **any** scenario directory with the same layout,
  including unseen ones (the grader re-runs it on fresh scenarios).

Python packages available (do not require anything else): `numpy`,
`opencv-python-headless`, `pillow`, `pytesseract`, `scipy` and the OS package
`tesseract-ocr`.

## Input layout

Each scenario directory contains:

| file             | meaning                                                              |
|------------------|----------------------------------------------------------------------|
| `grid.png`       | raster of a **9 x 9** arrangement of printed digits                  |
| `member.png`     | prose text image that contains one all-caps **secret token**         |
| `code.png`       | photograph of a short Python algorithm (see *Recovered code*)        |
| `toolpath.txt`   | plotter tool-path command log                                        |
| `general.json`   | JSON holding `x` (a numeric argument) and `render_a`, `render_b`     |
| `lin.csv`        | two-column points; most follow one line, some are outliers          |
| `box1.png`, `box2.png` | two views of the same textured plane (feature-matching pair) |
| `rig_a.csv`, `rig_b.csv` | two matched point sets (rigid correspondence)             |

The arrays/files may vary between scenarios: different grids, different probe
texts, different code literals, different tool-path primitives (including
degenerate ones such as a zero-area rectangle), and feature sets with heavier
outlier contamination. Never assume fixed numeric constants or a fixed count of
primitives or inliers.

## What to recover

### 1. Digit grid (from `grid.png`)
OCR/read the image and produce the exact 9 rows of 9 characters each, a digit
`0`-`9` per cell. Output as a list of nine strings (each length 9):
`["530078912", ...]`.

### 2. Two OCR-readable rasters (from `general.json`)
The JSON has fields `render_a` and `render_b`, which are natural-language phrases.
Render **each phrase into its own raster** such that the printed text is readable
by a character-recognition engine:
- write `render_a` → `<output_dir>/render_a.png`
- write `render_b` → `<output_dir>/render_b.png`

The verifier runs OCR on these two files and compares to the original phrases, so
the glyphs must render crisply (high-contrast, legible, silk-thin). Monochrome,
large black-on-white text is a reliable choice.

### 3. Secret token (from `member.png`)
`member.png` is a short piece of captions-style prose containing exactly one
all-caps secret token (a real dictionary word, e.g. `HARBOR`). Read the image,
extract the prose, and isolate that all-caps token. Output it as `member_secret`.

### 4. Transcribed algorithm (from `code.png`)
`code.png` is a photograph of this Python snippet (the numeric constants differ
per scenario):

```python
def compute(n):
  acc = 0
  for k in range(1, U):
    acc = acc + k
  off = Q
  acc = acc*n
  return acc + off
```

so the returned value is `acc*n + Q` with `acc = U*(U-1)/2`. Off-the-shelf OCR of
this photo is unreliable: it drops or mangles lines and characters (for example
operators and some tokens), so you must transcribe the algorithm's exact numeric
parameters and evaluate it. Any single misread changes the value. The argument
`n` is given in `general.json` as `x`. Output the integer result as `code_value`.

### 5. Recovered print-path word (from `toolpath.txt`)
The tool-path log is a small plotter command language. Parse it:

- `UNIT PREC<N>` — header, ignore.
- `RECT <x> <y> <w> <h>` — a rectangle primitive.
- `LINE <x1> <y1> <x2> <y2>` — a line segment primitive.
- `CIRC <cx> <cy> <r>` — a circle primitive.
- `POLY <x0> <y0> <x1> <y1> ...` — an open polyline primitive (2+ points).
- `SEAL <n1> <n2> ...` — the drawn word is encoded as numbers where `1=A, 2=B, ...`.

From this file:
1. Recover the drawn primitives **in order** and output them as `shapes`: a list
   of objects `{"t": "rect", "x":.., "y":.., "w":.., "h":..}`,
   `{"t":"line","x1":..,"y1":..,"x2":..,"y2":..}`,
   `{"t":"circ","cx":..,"cy":..,"r":..}` and
   `{"t":"poly","pts":[[x,y],...]}`. Recover every command, including degenerate
   ones (e.g. zero-area).
2. Decode the `SEAL` numbers into the tag word (A=1...Z=26) and output it as
   `print_word`. The drawn print-path represents exactly this word.
3. Re-render the recovered print-path to a raster as `<output_dir>/print.png`
   (draw the word's text, or the recovered shapes, in a form a OCR engine can
   read) and report `print_word`. The verifier OCRs `print.png` and checks it
   equals `print_word` — so you really must render and read it.

### 6. Robust geometric fits (feature matching)
Run robust geometric-model fits over the correspondence data and record inlier
counts, plus draw each fit to an image:

- Line fit on points from `lin.csv`. Determine the inliers of the best line via a
  robust method (e.g. RANSAC) under a ~2 px reprojection tolerance. Output
  `line_inliers` and draw them to `<out_dir>/fit_line.png`.
- Homography fit between `box1.png` and `box2.png` (views of a textured plane):
  detect + match features (e.g. ORB + hamming) and fit a planar homography
  robustly (e.g. cv2.findHomography RANSAC). Output `plane_inliers` (sum of the
  RANSAC mask) and draw `fit_a.png` / `fit_b.png`.
- Rigid fit over `rig_a.csv`/`rig_b.csv` (index-aligned correspondences with
  noise and outliers). Estimate the rigid transform robustly and count inliers
  to a small tolerance. Output `rigid_inliers` and draw `<out_dir>/fit_rigid.png`.

The verifier compares your reported counts to ground truth within a few inliers,
and requires that the four outcomes image files exist.

## `answer.json`

Your program must write `<output_dir>/answer.json` with exactly these keys:

```json
{
  "grid":            [/*9 strings of length 9*/],
  "member_secret":   "WORD",
  "code_value":      <int>,
  "print_word":      "TAGWORD",
  "shapes":          [/* list of primitives as above */],
  "line_inliers":   <int>,
  "plane_inliers":   <int>,
  "rigid_inliers":  <int>
}
```

Key spellings matter exactly (`line_inliers`, `plane_inliers`, `rigid_inliers`; the
keys above for the primitives and `print_word`).

## Constraints

- `/app/solve.py` must work on a fresh scenario directory with the same layout.
- All paths used inside the program must come from the two CLI arguments.
- Do not require network, system services, or anything beyond the installed
  packages and `tesseract-ocr`.

Write `/app/solve.py` and run it on the shipped scenario so `/app/answer.json`
and every other deliverable exists. The grader re-runs the program on additional
hidden scenarios and checks the exact same deliverables.