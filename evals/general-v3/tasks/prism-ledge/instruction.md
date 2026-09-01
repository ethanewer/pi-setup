# prism-ledge — a CPU vision-analysis pipeline

You are handed a small **vision clip** captured by a fixed overhead camera: a static
track scene with a single **moving subject** (an oval "runner") that rolls across the
frame and performs one short airborne jump part-way through. A short **printed label**
(upper-case letters/digits, 6 characters, no spaces) is painted on the track. Your job
is to build a self-contained analysis pipeline and a tiny C raster decoder, then run the
pipeline over the provided clip and produce the requested outputs.

Everything runs **on one CPU**; there is no GPU. The provided Python env already has
`torch`, `numpy`, `opencv-python-headless` (`cv2`), `pytesseract`, and the `tesseract`
binary, and `gcc` + `libpng` + `pkg-config` are available to compile C.

## Input bundle (shipped in the image at `/app/clip_v`)

A clip directory has this layout:

```
clip_v/
  background.png     # the empty static camera scene (8-bit grayscale PNG)
  frames/000.png     # one grayscale frame per time step, NNN.png (0..N-1)
        001.png ...  # each frame = background + the moving subject at that step
  sam_model.py       # module that defines TinySAM (see below)
  sam_weights.pt     # per-clip distilled-SAM checkpoint
  input.csv          # per-cell prompt manifest AND the output CSV schema
```

Every frame PNG and `background.png` are **8-bit grayscale, non-interlaced PNGs**
(`color type 0`, one sample per pixel). The subject is a connected bright shape moving
against the darker track; from the camera's point of view it is the only thing that
changes between the background and any frame (apart from its vertical motion during the
jump). The printed label is a static part of the background.

### The distilled SAM model (`sam_model.py`, `sam_weights.pt`)

`sam_model.py` defines a small PyTorch module:

```python
class TinySAM(nn.Module):
    def __init__(self, height, width): ...
    def forward(self, image): ...   # image: (B,1,H,W) float tensor normalised to [0,1]
```

`sam_weights.pt` is a **state_dict** giving the model the clip's static-scene prior and
lens parameters. Load it with `torch.load(..., map_location="cpu")` and
`model.load_state_dict(state)`, call `model.eval()`, then run inference with `torch.no_grad()`.
The model is a foreground-segmentation operator: `torch.sigmoid(model(image)) > 0.5`
selects exactly the moving-subject's pixels (a value of `1` where the pixel deviates from
the learned background prior, `0` elsewhere) for any input frame, at full resolution.
These masks are what the rest of the pipeline consumes.

### The manifest (`input.csv`)

`input.csv` has this header and one row per **cell**:

```
sample_id,cell,x0,y0,x1,y1,points,centroid,tag
```

- `x0,y0,x1,y1` are the (inclusive) pixel bounds of a rectangular **prompt region** (a cell).
- `points` and `centroid` are the **list-valued coordinate fields** you must fill in the
  output. In the input rows they are placeholder list literals (e.g. `[x0, y0, x1, y1]`
  for `points` and `[0, 0]` for `centroid`).

The manifest's cells are prompt rectangles: one region centered on the subject at the
reference moment (see **e**) and a few background-only regions (e.g. in the sky) that
never contain the subject. A cell that contains only background must yield an **empty**
polyline `[]`.

## Deliverables

Produce all three in `/app`:

1. **`/app/cdecode`** — a compiled C program (built with `gcc` and `libpng`) that decodes
   any 8-bit grayscale PNG and prints its **pixel matrix**: one line per row, `width`
   space-separated integers per line, each the 8-bit gray sample (0–255), row-major.
   Usage: `cdecode <png>`. Handle grayscale PNGs correctly (filters, expansion of low
   bit-depth, stripping 16-bit, gray conversion) so the printed values equal the raw
   samples. This decoder is the low-level matrix source for your pipeline.

2. **`/app/pipeline.py`** — a Python program:
   ```
   python3 pipeline.py <clip_dir> <out_dir>
   ```
   It must read the clip through your C decoder, run the SAM inference on CPU, do the
   tracking/event/mask analysis, and write **`<out_dir>/out.csv`** and
   **`<out_dir>/analysis.json`**.

3. **`/app/out.csv`** — the schema-preserving output, produced by *running* your pipeline
   on the visible clip:
   ```
   python3 /app/pipeline.py /app/clip_v /app
   ```

Make `/app/cdecode` and `/app/pipeline.py` executable.

## Required behaviour (this is what is verified)

### a. Raster decode (`/app/cdecode`)
Given any provided PNG it must print exactly the reference pixel matrix (the verifier
compares your `cdecode` output against an independent grayscale decode on a fresh PNG).

### b. Load the distilled SAM and run CPU inference
Your pipeline must actually import `sam_model.py`, load `sam_weights.pt`, and run CPU
inference (`model.eval()`, `torch.no_grad()`) to obtain the foreground mask for **every
frame**.

### c. Track the moving subject’s bounding extent (background subtraction)
Using the foreground masks, compute each frame’s foreground **bounding box** (min/max
x/y of the subject pixels). These are the per-frame `bboxes`.

### d. Infer takeoff / landing event boundaries
From the tracked vertical motion (the subject's centre-of-mass **y** over frames), detect
the airborne phase: compute the on-ground baseline (e.g. the median of the per-frame
centre y), and mark a frame airborne when its centre lies clearly above that baseline
(you pick a small pixel threshold). **takeoff** = first airborne frame,
**landing** = last airborne frame.

### e. Per-cell mask operator (prompt per rectangular region)
For each row of `input.csv`, segment the subject **within that cell** using the SAM
foreground of a single **reference frame** (use the takeoff frame you found; fall back to
the last frame if there is no jump). The per-cell mask is the foreground restricted to
that cell’s rectangle (in the **cell’s local coordinate frame**, top-left = `(0,0)`).

Then **normalise** each cell’s mask into a single connected, contiguous **polyline**
boundary such that:
- it is a single connected region (one outer contour),
- it does **not** overlap other cells’ masks (the cells are disjoint rectangles, keep
  your polyline inside its own cell),
- it is **not** the trivial prompt rectangle — the boundary must actually follow the
  subject (an empty/background-only cell must produce an **empty** polyline `[]`).

Write that polyline into the row’s `points` field as a **flat numeric list**
`[x0, y0, x1, y1, ...]` (alternating x, y) in the cell-local frame, and write the cell
mask’s centre-of-mass into `centroid` as `[cx, cy]` (empty `[]` for an empty cell).

### f. OCR the printed label
Recover the printed label from the track and read it with tesseract. Identify the bright
label strip (it is the brightest horizontal band in the lower half of the frame), crop/
binarise/scale it as needed, and OCR only `A–Z` and `0–9`. The result goes in
`analysis.json` as `ocr_text` (uppercase alphanumerics; drop anything that is not a letter
or digit).

### g. Preserve the input schema in `out.csv`
`out.csv` must have the **exact same header** and **same number of rows** as `input.csv`.
All columns are preserved; the `points` and `centroid` fields are the coordinate
values replaced with your refined list-valued fields. When read back, every `points` /
`centroid` field must parse (e.g. with `ast.literal_eval`) to a **flat list of numbers**.

## `analysis.json` format (exact key names)

```json
{
  "clip": "<clip dir name>",
  "n_frames": <int>,
  "height": <int>,
  "width": <int>,
  "bboxes": [[x0,y0,x1,y1], ...],      // length == n_frames
  "centroids": [[cx,cy], ...],          // length == n_frames
  "baseline_y": <float>,
  "takeoff_frame": <int>,               // -1 if none
  "landing_frame": <int>,               // -1 if none
  "ocr_text": "<uppercase alnum phrase>"
}
```

## Constraints

- Do **not** modify `background.png`, the frames, `sam_model.py`, `sam_weights.pt`, or
  the shipped `input.csv`.
- Your `pipeline.py` and `cdecode` must be **general**: the verifier will run them on
  hidden clips with different frame counts, image sizes, label phrases, jump windows, and
  cell grids. No hard-coding clip-specific numbers.
- The hidden clips are provided read-only at verify time; always write outputs to the
  output directory argument.
- No network access is available at runtime.

## What to produce / run

```bash
# 1. compile the C decoder
gcc -O2 -o /app/cdecode /app/cdecode.c $(pkg-config --cflags --libs libpng)
# 2. write /app/pipeline.py
# 3. run it on the shipped clip to produce the deliverables
python3 /app/pipeline.py /app/clip_v /app
```

The verifier will separately run your `pipeline.py` + `cdecode` on hidden clips and check
the raster decode, per-frame bboxes, takeoff/landing, per-cell polylines (single,
non-overlapping, non-trivial), the OCR phrase, and the `out.csv` schema against an
independent reference.
