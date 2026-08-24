# Item-066 (medium) — Normalize heterogeneous MobileSAM mask exports to one COCO-like dataset

A computer-vision team runs **MobileSAM** (a lightweight SAM variant) with several
export hooks on the same 96×96 fixture image.  The hook scripts were written by
different people, so the resulting annotations are stored in **five different mask
representations**, and one extra annotation is marked as a *crowd* region.  Your
job is to write a **normalizer** that reads `/app/data`, decodes every instance
mask regardless of representation, validates the geometry, and serializes the whole
thing into one **COCO-like JSON dataset** plus one **binary PNG per mask**, with a
**validation log**.

**Inspect the annotation schema before transforming anything**: start by reading
`/app/data/meta.json` and every mask file to see the exact shapes and formats.

## Input: `/app/data` (read-only, fixed)

- `meta.json`:
  ```json
  { "width": 96, "height": 96,
    "instances": [
      { "id": 1, "file": "masks/mask_01.png",         "category": "square",  "iscrowd": false },
      { "id": 2, "file": "masks/mask_02.rle.json",    "category": "square",  "iscrowd": false },
      { "id": 3, "file": "masks/mask_03.poly.json",   "category": "triangle","iscrowd": false },
      { "id": 4, "file": "masks/mask_04.pt",          "category": "circle",  "iscrowd": false },
      { "id": 5, "file": "masks/mask_05.npy",         "category": "square",  "iscrowd": false },
      { "id": 6, "file": "masks/mask_06.png",         "category": "hole",    "iscrowd": true  }
    ]}
  ```
- `masks/` — one file per instance, in a **mix of representations**:

  | id | file | representation | decode rule |
  |----|------|----------------|-------------|
  | 1 | `mask_01.png` | binary PNG, 0/255 grayscale | pixel value `>= 128` ⇒ mask pixel |
  | 2 | `mask_02.rle.json` | COCO compressed RLE `{"size":[H,W],"counts":[...]}` | row-major run-lengths (see below). Note: this mask has pixel (0,0) = 1, so its `counts` begins with a `0`. |
  | 3 | `mask_03.poly.json` | flat polygon `{"size":[H,W],"polygons":[[x0,y0,x1,y1,...]]}` | fill the **closed** polygon (see below). The stored polygon is deliberately **unclosed** — close it by appending the first point. |
  | 4 | `mask_04.pt` | PyTorch tensor of **float logits** (MobileSAM mask-logit output) | `mask = logits > 0` (SAM convention: threshold logits at 0, *not* 0.5) |
  | 5 | `mask_05.npy` | boolean numpy array | value directly ⇒ mask pixel |
  | 6 | `mask_06.png` | binary PNG, 0/255 grayscale, **iscrowd=true** | pixel value `>= 128` ⇒ mask pixel |

  Coordinates are `(col, row)`, origin top-left, `col in [0,96)`, `row in [0,96)`.

  **RLE codec (exactly)**: flatten the mask in row-major order to 0/1; the
  `counts` list is the alternating run lengths of that flat string (0-runs and
  1-runs, starting with a 0-run), with a single leading `0` added when the first
  pixel is `1`.

  **Polygon fill (exactly)**: round coordinates to integers, close the polygon
  (append the first point if missing), then fill it with the standard scanline
  fill used by OpenCV `fillPoly` (~= COCO visibility fill).  Points are inside
  96×96 here, but clip coordinates to `[0,95]` anyway as a safety check.
  A filled polygon is the geometry; a flat list with an odd number of entries is
  malformed — the verifier expects every emitted polygon to be closed and even.

## Deliverable — your program must write exactly these files

Write a normalizer (any language you like in the container — the reference tooling
is Python with `numpy`, `Pillow`, `opencv-python-headless`, `torch` installed).
Output must be:

1. `/app/out/annotations.json` — COCO-like:
   ```json
   {
     "images": [ {"id": 0, "file_name": "mosaic.png", "width": 96, "height": 96} ],
     "categories": [ {"id": <int>, "name": "<category from meta>"}, ... ],   // one per distinct category
     "annotations": [
       { "id": <instance id>, "image_id": 0, "category_id": <int>,
         "bbox": [x, y, w, h], "area": <int>, "iscrowd": <bool>,
         "segmentation": <see below> }, ... ]
   }
   ```
   One annotation per instance (same order as meta.json).  Every id 1..6 is
   present exactly once; `category_id` must point into your `categories` list and
   map back to the meta category name.
   - `bbox` = `[min_col, min_row, width, height]` with
     `width = max_col - min_col + 1`, `height = max_row - min_row + 1`; all ints.
   - `area` = number of mask pixels (a JSON int — cast numpy scalars).
   - non-crowd `segmentation`: a list of **closed** flat polygons (ints), each
     with first point repeated at the end, whose scanline fill reproduces the
     mask.
   - crowd `segmentation`: a dict `{"size": [96, 96], "counts": [...]}` using the
     exact RLE codec above, whose decode reproduces the mask.
2. `/app/out/masks/mask_01.png` … `mask_06.png` — one binary PNG per instance
   (0/255 grayscale) that matches the decoded mask exactly.
3. `/app/out/validation.log` — one line per instance, e.g.
   `id 3 polygon -> OK`, where the token after the id is the *source
   representation* you decoded from (`png`, `rle`, `polygon`, `logits`, or
   `npy`).  The log must contain a line starting `id N` for every N in 1..6, and
   must **not** contain the literal string `ERROR` anywhere.

## Steps

1. Inspect the schema (`meta.json` + each mask file).
2. Implement decoders for all five representations (and the crowd case) exactly
   as specified above.
3. Validate geometry: sizes vs `/app/data/meta.json`, integer coords, closed
   polygons, non-degenerate masks.  Diagnostics go to `validation.log`.
4. Serialize `/app/out/annotations.json`, the PNGs, and the log.
5. **Self-verify by round-trip**: decode your own `segmentation` and PNGs back
   and compare (IoU/pixel equality) against the decodes of the source masks —
   fix mismatches before finishing.

The verifier independently re-decodes the same five representations from the
fixtures and compares everything byte-for-byte/pixel-for-pixel.