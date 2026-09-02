# Lichen-mesa: CPU distilled-SAM prompt segmentation over survey tiles

An ecological survey drone captured several static **tiles**. Each tile ships
with a **distilled MobileSAM-style segmenter** checkpointed for that tile and a
manifest of **rectangular prompt regions** ("quadrats"). Your job is to build a
reusable per-cell segmentation program: run the distilled SAM on the **CPU**,
derive the foreground mask from each rectangular prompt, and emit per-cell
segmentation masks plus a tabular report.

Everything runs on one CPU; there is no GPU and no network access. The Python
environment already has `torch` (CPU), `numpy`, and `pillow`.

## Input tile directory (e.g. the visible `/app/survey/tile_alpha`)

```
tile_dir/
  scene.png        # 8-bit grayscale PNG, the static scene (height H, width W)
  sam_model.py     # defines class TinySAM for this tile (see below)
  sam_weights.pt   # per-tile distilled-SAM state_dict (torch.save)
  prompts.csv      # rectangular prompt regions AND the report row order
```

`prompts.csv` has the header `cell_id,x0,y0,x1,y1` and one row per **cell**:
a rectangular prompt region with **inclusive** pixel bounds, where `x` is the
column index and `y` is the row index (`0 <= x0 <= x1 < W`, `0 <= y0 <= y1 < H`).
A cell may fully contain an anomaly, may **clip** through one, or may lie
entirely on background.

## The distilled SAM (`sam_model.py`, `sam_weights.pt`)

`sam_model.py` defines:

```python
class TinySAM(nn.Module):
    def forward(self, image): ...   # image: (B,1,H,W) float tensor in [0,1]
```

Load the per-tile weights with `torch.load(..., map_location="cpu")`, apply
`model.load_state_dict(state)`, call `model.eval()`, and run inference under
`torch.no_grad()` — all **on the CPU** (device `cpu`). The model is a
foreground-segmentation operator: `torch.sigmoid(model(image)) > 0.5` selects
exactly the anomalous pixels of `scene.png` at full resolution. Normalise the
scene to `[0, 1]` as `uint8 gray / 255.0`.

## Deliverables (all required, all under `/app`)

1. **`/app/survey.py`** — a reusable program:
   ```
   python3 /app/survey.py <tile_dir> <out_dir>
   ```
   It must load `scene.png`, `sam_model.py` / `sam_weights.pt` from the given
   tile directory (import the tile's own module — do not copy or inline model
   code), run the CPU inference **once per tile**, and write the three output
   artifacts below into `<out_dir>` (created if missing). It must work on any
   tile conforming to this layout, not only the visible one.

2. Run it on the visible tile to produce the answer bundle:
   ```
   python3 /app/survey.py /app/survey/tile_alpha /app/answer
   ```

### Output artifacts (written into the out dir)

**`masks.npz`** — a compressed npz (`numpy.savez_compressed`) with one array
per cell, keyed by the cell's `cell_id`, in `prompts.csv` row order. Each array
is the **cell-local** segmentation mask: `dtype=uint8`, values `0/1`, shape
`(y1-y0+1, x1-x0+1)` (rows, columns). It is the full-frame foreground mask
restricted to the cell's rectangle, with the cell's top-left corner at local
`(0, 0)`.

**`cells.csv`** — header exactly:
```
cell_id,area,cx,cy,bx0,by0,bx1,by1
```
one row per cell in `prompts.csv` row order, where
- `area` = number of foreground pixels in the cell's mask (`int`),
- `cx, cy` = centroid of the mask **in cell-local coordinates**, formatted
  `%.3f` (column index first),
- `bx0,by0,bx1,by1` = bounding box of the mask **in cell-local inclusive
  coordinates** (ints),
- an **empty cell** (zero foreground pixels) has `area=0`, `cx=-1.000`,
  `cy=-1.000`, and all four bbox fields `-1`.

**`analysis.json`** — valid JSON with exactly these keys:
```json
{"tile": "<tile dir base name>", "n_cells": <int>, "empty_cells": <int>,
 "foreground_pixels": <int>}
```
`foreground_pixels` is the number of foreground pixels of the **full-frame**
mask (before per-cell restriction). `n_cells` is the number of prompt rows and
`empty_cells` the number of cells with zero foreground pixels.

## Constraints

- The verifier runs `/app/survey.py` unchanged on hidden tiles (different
  sizes, blob layouts, cell counts and rect placements), so the program must be
  fully driven by the tile's own files.
- Deterministic: same tile → byte-identical `cells.csv` and `analysis.json`
  and identical masks. No network, CPU only.
- Do not modify anything inside `/app/survey/`.
