#!/bin/bash
set -euo pipefail

# Oracle for item-066-hard: embed and run the reference consolidator, which
# decodes all six representations, validates geometry, drops empties, reports
# size mismatches and overlaps, and serializes /app/out.
cat > /tmp/ref_consolidate.py <<'PYEOF'
#!/usr/bin/env python3
"""Reference consolidator for item-066-hard."""
import json
import os

import numpy as np
from PIL import Image
import cv2
import torch

SRC = "/app/data"
OUT = "/app/out"
H = W = 128

LOG = []


def log_line(s):
    LOG.append(s)


# ---------------------------------------------------------------- decoders
def decode_png(path):
    return np.array(Image.open(path).convert("L")) >= 128


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
    mask = rle_decode(d["counts"], (H, W))
    return mask, d["size"]


def decode_vrle(path):
    d = json.load(open(path))
    px = np.array(d["pixels"], dtype=np.uint8).reshape(H, W)
    return px.astype(bool), d["size"]


def decode_polygon(path):
    d = json.load(open(path))
    canvas = np.zeros((H, W), np.uint8)
    for flat in d["polygons"]:
        if len(flat) % 2 != 0 or len(flat) < 4:
            continue
        pts = np.round(np.array(flat, dtype=np.float64).reshape(-1, 2)).astype(np.int32)
        pts = np.clip(pts, 0, [W - 1, H - 1])
        if len(pts) < 3:
            continue
        closed = np.vstack([pts, pts[:1]])
        cv2.fillPoly(canvas, [closed], 1)
    return canvas.astype(bool), d["size"]


def decode_pt(path):
    t = torch.load(path, map_location="cpu", weights_only=False)
    return t.numpy() > 0, [H, W]


def decode_npy(path):
    a = np.load(path)
    return a.astype(bool), [H, W]


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


def srctype_of(name):
    if name.endswith(".png"):
        return "png"
    if name.endswith(".rle.json"):
        return "rle"
    if name.endswith(".vrle.json"):
        return "vrle"
    if name.endswith(".poly.json"):
        return "polygon"
    if name.endswith(".pt"):
        return "logits"
    if name.endswith(".npy"):
        return "npy"
    raise RuntimeError(f"unknown format: {name}")


def main():
    meta = json.load(open(os.path.join(SRC, "meta.json")))
    assert meta["width"] == W and meta["height"] == H

    cat_names = []
    for inst in meta["instances"]:
        if inst["category"] not in cat_names:
            cat_names.append(inst["category"])
    categories = [{"id": i + 1, "name": name} for i, name in enumerate(cat_names)]
    cat_id = {c["name"]: c["id"] for c in categories}

    os.makedirs(os.path.join(OUT, "masks"), exist_ok=True)
    annotations, kept_masks, kept_ids = [], [], []

    for inst in meta["instances"]:
        iid = inst["id"]
        path = os.path.join(SRC, inst["file"])
        name = os.path.basename(path)
        srctype = srctype_of(name)

        if srctype == "png":
            mask, declared = decode_png(path), [H, W]
        elif srctype == "rle":
            mask, declared = decode_rle(path)
        elif srctype == "vrle":
            mask, declared = decode_vrle(path)
        elif srctype == "polygon":
            mask, declared = decode_polygon(path)
        elif srctype == "logits":
            mask, declared = decode_pt(path)
        else:
            mask, declared = decode_npy(path)

        if declared != [H, W]:
            log_line(f"WARN size-mismatch id {iid}: declared {declared}, using true {[H, W]}")

        if not mask.any():
            log_line(f"WARN drop id {iid} empty mask ({srctype})")
            continue

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
        kept_masks.append(mask)
        kept_ids.append(iid)
        Image.fromarray((mask.astype(np.uint8) * 255)).save(
            os.path.join(OUT, "masks", f"mask_{iid:02d}.png"))
        log_line(f"id {iid} {srctype} -> OK")

    # overlaps among kept instances
    for a in range(len(kept_ids)):
        for b in range(a + 1, len(kept_ids)):
            shared = int(np.logical_and(kept_masks[a], kept_masks[b]).sum())
            if shared > 0:
                log_line(f"WARN overlap id {kept_ids[a]} id {kept_ids[b]} {shared}")

    payload = {
        "images": [{"id": 0, "file_name": "mosaic.png", "width": W, "height": H}],
        "categories": categories,
        "annotations": annotations,
    }
    with open(os.path.join(OUT, "annotations.json"), "w") as f:
        json.dump(payload, f, indent=2)
    with open(os.path.join(OUT, "validation.log"), "w") as f:
        f.write("\n".join(LOG) + "\n")
    print("reference consolidator done")


if __name__ == "__main__":
    main()
PYEOF

rm -rf /app/out
python3 /tmp/ref_consolidate.py
echo "solve.sh: /app/out written"