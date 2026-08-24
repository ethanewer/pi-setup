#!/usr/bin/env python3
"""Deterministic heterogeneous mask fixtures for item-066 (medium).

Builds <out_dir> with meta.json + masks/ where the same binary dataset is stored
in five different representations plus one crowd mask:

  id 1  PNG 0/255       rectangle   (rows 10..39, cols 20..59)
  id 2  COCO RLE json   L-shape     (flat[0] == 1: leading-zero counts)
  id 3  polygon json    triangle    (flat coords, deliberately UNCLOSED)
  id 4  PyTorch .pt     circle      (MobileSAM-style float logits; mask = logits > 0)
  id 5  numpy .npy      rectangle   (bool ndarray)
  id 6  PNG 0/255       donut       (iscrowd=True -> downstream must emit COCO RLE)

Deterministic: no randomness, fixed shapes.  Semantics are documented in
instruction.md; the verifier re-decodes these fixtures independently.
"""
import json
import os
import sys

import numpy as np
from PIL import Image
import cv2
import torch

H = W = 96


def rect(r0, r1, c0, c1):
    m = np.zeros((H, W), dtype=bool)
    m[r0:r1, c0:c1] = True
    return m


def l_shape():
    m = np.zeros((H, W), dtype=bool)
    m[0:40, 10:25] = True   # stem: rows 0..39, cols 10..24
    m[40:60, 10:50] = True  # base: rows 40..59, cols 10..49
    return m


def mask_from_polygon(flat):
    """Fill the closed version of a flat [x0,y0,x1,y1,...] polygon."""
    pts = np.array(flat, dtype=np.float64).reshape(-1, 2)
    pts = np.round(pts).astype(np.int32)
    closed = np.vstack([pts, pts[:1]])
    canvas = np.zeros((H, W), np.uint8)
    cv2.fillPoly(canvas, [closed], 1)
    return canvas.astype(bool)


def circle_logits(cx, cy, r):
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    logits = np.clip(3.0 * (r - d) / 2.0, -3.0, 3.0)
    return logits.astype(np.float32)


def donut(cy, cx, r_out, r_in):
    yy, xx = np.mgrid[0:H, 0:W]
    d = (xx - cx) ** 2 + (yy - cy) ** 2
    return (d <= r_out ** 2) & (d >= r_in ** 2)


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


def build(out):
    masks_dir = os.path.join(out, "masks")
    os.makedirs(masks_dir, exist_ok=True)

    m1 = rect(10, 40, 20, 60)
    Image.fromarray((m1.astype(np.uint8) * 255)).save(os.path.join(masks_dir, "mask_01.png"))

    m2 = l_shape()
    json.dump({"size": [H, W], "counts": rle_encode(m2)},
              open(os.path.join(masks_dir, "mask_02.rle.json"), "w"))

    tri = [20, 70, 50, 30, 80, 70]          # unclosed (first point not repeated)
    m3 = mask_from_polygon(tri)
    json.dump({"size": [H, W], "polygons": [tri]},
              open(os.path.join(masks_dir, "mask_03.poly.json"), "w"))

    m4 = circle_logits(48, 48, 20) > 0.0
    torch.save(torch.from_numpy(circle_logits(48, 48, 20)),
               os.path.join(masks_dir, "mask_04.pt"))

    m5 = rect(5, 31, 70, 92)
    np.save(os.path.join(masks_dir, "mask_05.npy"), m5)

    m6 = donut(72, 24, 22, 8)
    Image.fromarray((m6.astype(np.uint8) * 255)).save(os.path.join(masks_dir, "mask_06.png"))

    instances = [
        {"id": 1, "file": "masks/mask_01.png", "category": "square", "iscrowd": False},
        {"id": 2, "file": "masks/mask_02.rle.json", "category": "square", "iscrowd": False},
        {"id": 3, "file": "masks/mask_03.poly.json", "category": "triangle", "iscrowd": False},
        {"id": 4, "file": "masks/mask_04.pt", "category": "circle", "iscrowd": False},
        {"id": 5, "file": "masks/mask_05.npy", "category": "square", "iscrowd": False},
        {"id": 6, "file": "masks/mask_06.png", "category": "hole", "iscrowd": True},
    ]
    json.dump({"width": W, "height": H, "instances": instances},
              open(os.path.join(out, "meta.json"), "w"), indent=2)
    print("fixtures written to", out)


if __name__ == "__main__":
    build(sys.argv[1])