#!/bin/bash
# Real oracle for lichen-mesa: writes the reusable per-cell segmentation
# program (/app/survey.py) and runs it on the visible tile to produce the
# /app/answer bundle. Never reads /tests.
#
# Optional args for authoring-time expected-generation:
#   bash solve.sh [tile_dir out_dir]   (defaults: visible tile -> /app/answer)
set -eu

TILE="${1:-/app/survey/tile_alpha}"
OUT="${2:-/app/answer}"

SOLVER="/app/survey.py"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
"""Per-cell distilled-SAM segmentation over a survey tile (CPU only)."""
import csv
import json
import os
import sys

import numpy as np
import torch
from PIL import Image


def main(tile_dir, out_dir):
    tile_dir = os.path.abspath(tile_dir)
    out_dir = os.path.abspath(out_dir)
    os.makedirs(out_dir, exist_ok=True)

    # ---- scene -----------------------------------------------------------
    img = np.asarray(Image.open(os.path.join(tile_dir, "scene.png")).convert("L"))
    H, W = img.shape
    x = torch.from_numpy(img.astype(np.float32) / 255.0)[None, None]  # (1,1,H,W)

    # ---- load the tile's own distilled SAM and run CPU inference ----------
    if tile_dir not in sys.path:
        sys.path.insert(0, tile_dir)
    from sam_model import TinySAM

    model = TinySAM(H, W)
    state = torch.load(os.path.join(tile_dir, "sam_weights.pt"),
                       map_location="cpu")
    model.load_state_dict(state)
    model.eval()
    with torch.no_grad():
        logits = model(x)
    fg = (torch.sigmoid(logits)[0, 0].numpy() > 0.5)
    foreground_pixels = int(fg.sum())

    # ---- per-prompt-rectangle cell masks ----------------------------------
    with open(os.path.join(tile_dir, "prompts.csv"), newline="") as fh:
        rows = list(csv.DictReader(fh))

    masks = {}
    cell_rows = []
    empty = 0
    for r in rows:
        cid = r["cell_id"]
        x0, y0, x1, y1 = int(r["x0"]), int(r["y0"]), int(r["x1"]), int(r["y1"])
        sub = fg[y0:y1 + 1, x0:x1 + 1]
        m = sub.astype(np.uint8)
        masks[cid] = m
        area = int(m.sum())
        if area == 0:
            empty += 1
            cell_rows.append((cid, 0, "-1.000", "-1.000", -1, -1, -1, -1))
        else:
            ys, xs = np.nonzero(m)
            cx = float(xs.mean())
            cy = float(ys.mean())
            cell_rows.append((cid, area, "%.3f" % cx, "%.3f" % cy,
                              int(xs.min()), int(ys.min()),
                              int(xs.max()), int(ys.max())))

    np.savez_compressed(os.path.join(out_dir, "masks.npz"), **masks)

    with open(os.path.join(out_dir, "cells.csv"), "w", newline="") as fh:
        fh.write("cell_id,area,cx,cy,bx0,by0,bx1,by1\n")
        for row in cell_rows:
            fh.write("%s,%d,%s,%s,%d,%d,%d,%d\n" % row)

    analysis = {
        "tile": os.path.basename(os.path.normpath(tile_dir)),
        "n_cells": len(rows),
        "empty_cells": empty,
        "foreground_pixels": foreground_pixels,
    }
    with open(os.path.join(out_dir, "analysis.json"), "w") as fh:
        json.dump(analysis, fh, indent=2)

    print("SURVEY_OK tile=%s cells=%d" % (analysis["tile"], analysis["n_cells"]))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
PY

chmod +x "$SOLVER"

# ---- 2. Run the produced program on the requested tile ---------------------
python3 "$SOLVER" "$TILE" "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$OUT"
