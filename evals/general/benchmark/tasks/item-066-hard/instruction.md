# Item-066 (hard) — Consolidate corrupted, heterogeneous MobileSAM mask exports

A research lab ran **MobileSAM** over a **128×128 tile-mosaic** and exported the
masks through a dozen different hook scripts.  Several exports are **corrupt or
adversarial** (empty masks, degenerate polygons, out-of-bounds coordinates, wrong
declared sizes, overlapping occlusions), and the same binary mask crop up in many
representations.  Your job is to write a **consolidator** that:

1. **inspects the annotation schema first** — read `/app/data/meta.json` and every
   mask file before deciding how to decode them;
2. decodes every instance mask regardless of representation (heterogeneous
   formats, incl. **COCO RLE**, **uncompressed VRLE**, **polygons**, **PNG
   binary and soft/anti-aliased grayscale**, **PyTorch `.pt` logit tensors**
   (MobileSAM mask-logit output), **numpy `.npy`**);
3. **validates geometry**: sizes vs image bounds, integer coords, closed polygons,
   clipping of out-of-bounds vertices, emptiness detection;
4. **serializes** one COCO-like dataset + binary PNG per kept mask + a validation
   log, flagging every anomaly (drops, size mismatches, overlaps) explicitly.

## Input: `/app/data` (read-only, fixed)

- `meta.json` — `{"width": 128, "height": 128, "instances": [ ... 20 entries ... ]}`
  with fields `id` (1..20), `file`, `category`, `iscrowd`.  The order in the file
  is the canonical order you must preserve in your output.
- `masks/mask_<NN>.<ext>` — each instance stored in **one** of these
  representations (all coordinates are `(col, row)`, origin top-left, `col in
  [0,128)`, `row in [0,128)`):

  | ext | meaning | decode rule |
  |-----|---------|-------------|
  | `mask_XX.png` | grayscale PNG | `pixel >= 128` ⇒ mask pixel. Applies to **binary** (0/255) exports **and** **soft** exports with anti-aliased values (some `mask_05.png`-style soft pixels are deliberately BELOW 128 — they must not leak into the mask). |
  | `mask_XX.rle.json` | COCO compressed RLE `{"size":[h,w],"counts":[...]}` | row-major alternating run-lengths (codec below). A leading `0` is present when the first pixel is `1`. |
  | `mask_XX.vrle.json` | uncompressed VRLE `{"size":[h,w],"pixels":[0/1 per pixel]}` | row-major list of 0/1, length `h*w`. |
  | `mask_XX.poly.json` | `{"size":[h,w],"polygons":[[x0,y0,...],...]}` | per polygon: round to ints, **clip** every coordinate to `[0,127]`, **close** it (append first point if missing), then scanline-fill (OpenCV `fillPoly` semantics); union of all polygons. A polygon with **fewer than 3 distinct vertices after closing/clipping** contributes nothing (degenerate ⇒ empty mask). |
  | `mask_XX.pt` | PyTorch float tensor (MobileSAM mask **logits**) | `mask = logits > 0` (threshold at 0, not 0.5). |
  | `mask_XX.npy` | boolean (or 0/1 integer) ndarray | value directly ⇒ mask pixel (nonzero = mask). |

  **RLE codec (exactly)**: flatten the mask row-major to 0/1; `counts` = alternating
  run lengths (0-runs and 1-runs, starting with a 0-run), with a single leading
  `0` prepended when the first pixel is `1`.

## Geometry validation rules (bind, exactly)

1. **Size validation**: every RLE/VRLE/polygon JSON declares a `size`.  If the
   declared size differs from the image size `[128, 128]`, **do not trust it** —
   recover the true shape from the payload (decoded run lengths / pixel count /
   rasterization bounds), log `WARN size-mismatch id <N>`, and continue using the
   true shape.  This is a warning, not a drop.  (Exactly one instance, id 19,
   declares a wrong size.)
2. **Empty masks**: after decoding, if the candidate mask has **zero** pixels
   (this includes degenerate polygons and all-negative logit tensors), the
   instance is **DROPPED**: it gets **no** annotation, **no** PNG, and the log
   gets `WARN drop id <N>` (mention `drop` and `id <N>`).  Applies to crowd and
   non-crowd alike.  (Exactly ids 10, 11, 12 and 18 are empty.)
3. **Overlaps**: kept instances may genuinely overlap (occlusion).  For every
   pair `(a, b)` of **kept** instances whose masks share ≥ 1 pixel, the log must
   contain a line with the literal `overlap`, both `id a` and `id b`, and the
   number of shared pixels (e.g. `WARN overlap id 4 id 14 213`).
4. Every emitted coordinate must be an integer; every emitted polygon must be
   **closed** (first point == last point) and even-length.

## Deliverable — exactly these files under `/app/out`

1. `/app/out/annotations.json` — COCO-like:
   ```json
   {
     "images": [ {"id": 0, "file_name": "mosaic.png", "width": 128, "height": 128} ],
     "categories": [ {"id": <int>, "name": "<category>"}, ... ],   // one per distinct category
     "annotations": [ { "id": <int>, "image_id": 0, "category_id": <int>,
                        "bbox": [x, y, w, h], "area": <int>, "iscrowd": <bool>,
                        "segmentation": <see below> }, ... ]
   }
   ```
   - Exactly the **kept** instances (empty ones dropped), in meta.json order.
   - `bbox` = `[min_col, min_row, width, height]`, `width = max_col-min_col+1`,
     `height = max_row-min_row+1`; ints; within image bounds.
   - `area` = number of mask pixels (JSON int — cast numpy scalars).
   - non-crowd `segmentation`: list of **closed** flat polygons (ints), whose
     scanline fill reproduces the mask exactly (~overlap IoU ≥ 0.995 suffices).
   - crowd `segmentation`: dict `{"size": [128, 128], "counts": [...]}` (exact
     codec above) whose decode reproduces the mask.
2. `/app/out/masks/mask_<NN>.png` — one 0/255 binary PNG **per kept instance**
   (two-digit zero-padded id), pixel-identical to the decoded mask.  No PNGs for
   dropped instances.
3. `/app/out/validation.log` — lines:
   - per kept instance: `id <N> <srctype> -> OK` where srctype ∈
     `png | rle | vrle | polygon | logits | npy`;
   - per dropped instance: `WARN drop id <N> ...` (must contain `drop`);
   - the size mismatch: `WARN size-mismatch id 19`;
   - per overlapping kept pair: `WARN overlap id <a> id <b> <px>`;
   - and the literal string `ERROR` must NOT appear anywhere in the log.

## Steps

1. Inspect the schema: dump `meta.json`, check sizes, count instances.
2. Implement all six decoders exactly as specified.
3. Apply geometry validation (size check → clip → close → fill; empty ⇒ drop).
4. Detect overlaps between kept masks and write the log.
5. Serialize `/app/out` (annotations.json, PNGs, log).
6. **Round-trip self-verify before optimizing** anything: decode your own
   `segmentation` and PNGs back to binary masks, compare pixel-for-pixel with
   your decodes of the fixtures, and confirm your dropped/overlap lists match
   what a fresh decode of `/app/data` gives.  Iterate until clean.

The verifier independently re-decodes every fixture representation and recomputes
kept sets, masks, bbox/area, RLE/polygon round-trips, overlap pairs and log lines.