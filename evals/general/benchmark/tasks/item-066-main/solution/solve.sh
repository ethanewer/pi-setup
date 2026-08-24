#!/bin/bash
set -euo pipefail

# Oracle for item-066-main: embed and run the reference normalizer, which
# decodes all five representations + crowd, validates, and writes /app/out.
cat > /tmp/ref_normalize.py <<'PYEOF'
#!/usr/bin/env python3
"""Reference normalizer for item-066-main."""
import json
import os
import sys

import numpy as np
from PIL import Image
import cv2
import torch

SRC = "/app/data"
OUT = "/app/out"
H = W = 96

LOG = []


def log_line(s):
    LOG.append(s)


# ---------------------------------------------------------------- decoders
def decode_png(path):
    arr = np.array(Image.open(path).convert("L"))
    return arr >= 128


def rle_decode(counts, shape):
    m = np.zeros(int(np.prod(shape)), dtype=np.uint8)
    i, v = 0, 0
    for c in counts:
        m[i:i + c] = v
        i += c
        v ^= 1
    return m.reshape(shape).astype(bool)


def decode_rle(path):
    d = json.load(open(path))
    size = d["size"]
    mask = rle_decode(d["counts"], tuple(size))
    return mask, size


def decode_polygon(path):
    d = json.load(open(path))
    size = d["size"]
    canvas = np.zeros((size[0], size[1]), np.uint8)
    for flat in d["polygons"]:
        if len(flat) % 2 != 0:
            continue
        pts = np.array(flat, dtype=np.float64).reshape(-1, 2)
        pts = np.round(pts).astype(np.int32)
        pts = np.clip(pts, 0, [size[1] - 1, size[0] - 1])
        closed = np.vstack([pts, pts[:1]])
        cv2.fillPoly(canvas, [closed], 1)
    return canvas.astype(bool), size


def decode_pt(path):
    t = torch.load(path, map_location="cpu", weights_only=False)
    return t.numpy() > 0, t.shape


def decode_npy(path):
    a = np.load(path)
    return a.astype(bool), a.shape


# ---------------------------------------------------------------- geometry
def bbox_area(mask):
    ys, xs = np.nonzero(mask)
    x0, y0 = int(xs.min()), int(ys.min())
    w, h = int(xs.max()) - x0 + 1, int(ys.max()) - y0 + 1
    return [x0, y0, w, h], int(mask.sum())


def rle_encode(mask):
    flat = mask.ravel().astype(np.uint8)
    runs = []
    i, n = 0, len(flat)
    while i < n:
        j = i
        while j < n and flat[j] == flat[i]:
            j += 1
        runs.append(j - i)
        i = j
    if flat[0] == 1:
        runs = [0] + runs
    return runs


def polygons_from_mask(mask):
    cnts, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_EXTERNAL,
                               cv2.CHAIN_APPROX_SIMPLE)
    polys = []
    for c in cnts:
        pts = c.reshape(-1, 2).tolist()
        if pts and pts[0] != pts[-1]:
            pts.append(pts[0])
        polys.append([int(v) for p in pts for v in p])
    return polys


# ---------------------------------------------------------------- main
def main():
    meta = json.load(open(os.path.join(SRC, "meta.json")))
    assert meta["width"] == W and meta["height"] == H

    cat_names = []
    for inst in meta["instances"]:
        if inst["category"] not in cat_names:
            cat_names.append(inst["category"])
    categories = [{"id": i + 1, "name": n} for i, n in enumerate(cat_names)]
    cat_id = {c["name"]: c["id"] for c in categories}

    os.makedirs(os.path.join(OUT, "masks"), exist_ok=True)
    annotations = []

    for inst in meta["instances"]:
        iid = inst["id"]
        path = os.path.join(SRC, inst["file"])
        name = os.path.basename(path)

        if name.endswith(".png"):
            mask, srctype = decode_png(path), "png"
        elif name.endswith(".rle.json"):
            mask, _ = decode_rle(path)
            srctype = "rle"
        elif name.endswith(".poly.json"):
            mask, _ = decode_polygon(path)
            srctype = "polygon"
        elif name.endswith(".pt"):
            mask, _ = decode_pt(path)
            srctype = "logits"
        elif name.endswith(".npy"):
            mask, _ = decode_npy(path)
            srctype = "npy"
        else:
            raise RuntimeError(f"unknown format for {name}")

        assert mask.shape == (H, W), f"id {iid}: bad shape {mask.shape}"
        assert mask.any(), f"id {iid}: empty mask"

        bbox, area = bbox_area(mask)
        if inst["iscrowd"]:
            seg = {"size": [H, W], "counts": rle_encode(mask)}
        else:
            seg = polygons_from_mask(mask)

        annotations.append({
            "id": iid, "image_id": 0, "category_id": cat_id[inst["category"]],
            "bbox": bbox, "area": area, "iscrowd": inst["iscrowd"],
            "segmentation": seg,
        })
        Image.fromarray((mask.astype(np.uint8) * 255)).save(
            os.path.join(OUT, "masks", f"mask_{iid:02d}.png"))
        log_line(f"id {iid} {srctype} -> OK")

    payload = {
        "images": [{"id": 0, "file_name": "mosaic.png", "width": W, "height": H}],
        "categories": categories,
        "annotations": annotations,
    }
    with open(os.path.join(OUT, "annotations.json"), "w") as f:
        json.dump(payload, f, indent=2)
    with open(os.path.join(OUT, "validation.log"), "w") as f:
        f.write("\n".join(LOG) + "\n")
    print("reference normalizer done")


if __name__ == "__main__":
    main()
PYEOF

rm -rf /app/out
python3 /tmp/ref_normalize.py
echo "solve.sh: /app/out written"