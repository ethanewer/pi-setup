#!/usr/bin/env python3
"""Deterministic, adversarial heterogeneous mask fixtures for item-066 (hard).

Builds <out_dir> with meta.json + masks/ for a 128x128 mosaic.  Twenty
instances mix ten source representations and deliberately corrupt exports:

  id  1 png-binary        square    rect rows 8..48  cols 8..40
  id  2 vrle-uncompressed rect     L-shape (flat[0]==1)
  id  3 poly-closed       triangle  (10,90),(60,20),(110,90),(10,90)
  id  4 pt-logits         circle    center (100,30) r=18
  id  5 png-soft          ellipse   center (30,110) rx=24 ry=12, AA band < 128
  id  6 rle (lead-0)      blob      disk (4,4) r=6  (covers pixel (0,0))
  id  7 png-binary CROWD  ring      donut center (64,64) rout=22 rin=9
  id  8 poly-unclosed     pentagon  center (104,104) r=12 (4 of 5 verts given)
  id  9 poly-out-of-bounds star     center (64,20) translated up (some y<0)
  id 10 rle-all-zero      rect      EMPTY -> must be dropped
  id 11 png-all-zero      triangle  EMPTY -> must be dropped
  id 12 poly-degenerate   circle    single point [[64,64,64,64]] -> EMPTY -> dropped
  id 13 npy-bool          square    rect rows 70..115 cols 70..115
  id 14 rle               square    rect rows 22..58  cols 90..120
  id 15 poly-closed       pentagon  center (40,50) r=14
  id 16 png-binary        ellipse   superellipse center (15,108) a=10 b=8
  id 17 pt-logits         blob      union disk(90,80,14) + disk(78,92,10)
  id 18 pt-all-negative   blob      EMPTY logits -> must be dropped
  id 19 rle size-mismatch ring     disk (118,40) r=10, declared size [64,128] (WRONG)
  id 20 vrle CROWD        blob      disk (60,110) r=12

Several kept masks genuinely overlap (occlusion); overlaps must be reported in
the validation log.  Deterministic: no randomness.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image
import cv2
import torch

H = W = 128


# ------------------------------------------------------------ shape helpers
def rect(r0, r1, c0, c1):
    m = np.zeros((H, W), dtype=bool)
    m[r0:r1, c0:c1] = True
    return m


def l_shape():
    m = np.zeros((H, W), dtype=bool)
    m[8:40, 8:20] = True    # stem
    m[30:60, 8:45] = True   # base
    return m


def disk(cx, cy, r):
    yy, xx = np.mgrid[0:H, 0:W]
    return (xx - cx) ** 2 + (yy - cy) ** 2 <= r ** 2


def donut(cx, cy, r_out, r_in):
    yy, xx = np.mgrid[0:H, 0:W]
    d = (xx - cx) ** 2 + (yy - cy) ** 2
    return (d <= r_out ** 2) & (d >= r_in ** 2)


def superellipse(cx, cy, a, b, n=4):
    yy, xx = np.mgrid[0:H, 0:W]
    return (np.abs((xx - cx) / a) ** n + np.abs((yy - cy) / b) ** n) <= 1.0


def triangle():
    return mask_from_polygon([10, 90, 60, 20, 110, 90, 10, 90])


def pentagon(cx, cy, r):
    pts = []
    for k in range(5):
        th = math.radians(-90 + 72 * k)
        pts.append((cx + r * math.cos(th), cy + r * math.sin(th)))
    flat = [int(round(float(x))) for p in pts for x in p]
    return mask_from_polygon(flat), flat


def star_points(cx, cy, r_out, r_in, ty=0.0):
    pts = []
    for k in range(5):
        th = math.radians(-90 + 72 * k)
        pts.append((cx + r_out * math.cos(th), cy + r_out * math.sin(th) + ty))
        th2 = math.radians(-54 + 72 * k)
        pts.append((cx + r_in * math.cos(th2), cy + r_in * math.sin(th2) + ty))
    return pts  # outer, inner, outer, inner, ... around the loop


def logits_banded(cx, cy, r):
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    return np.clip(3.0 * (r - d) / 2.0, -3.0, 3.0).astype(np.float32)


def mask_from_polygon(flat):
    pts = np.round(np.array(flat, dtype=np.float64).reshape(-1, 2)).astype(np.int32)
    pts = np.clip(pts, 0, [W - 1, H - 1])
    closed = np.vstack([pts, pts[:1]])
    canvas = np.zeros((H, W), np.uint8)
    cv2.fillPoly(canvas, [closed], 1)
    return canvas.astype(bool)


# ------------------------------------------------------------ codecs
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


def resize_soft(mask):
    return (mask.astype(np.uint8) * 255)


# ------------------------------------------------------------ main
def build(out):
    masks_dir = os.path.join(out, "masks")
    os.makedirs(masks_dir, exist_ok=True)

    def save_png(name, mask, soft=False):
        if soft:
            arr = np.zeros((H, W), np.uint8)
            arr[mask] = 240
            Image.fromarray(arr).save(os.path.join(masks_dir, name))
        else:
            Image.fromarray((mask.astype(np.uint8) * 255)).save(
                os.path.join(masks_dir, name))

    m = {}

    m[1] = rect(8, 48, 8, 40)
    save_png("mask_01.png", m[1])

    m[2] = l_shape()
    json.dump({"size": [H, W], "pixels": m[2].ravel().astype(np.uint8).tolist()},
              open(os.path.join(masks_dir, "mask_02.vrle.json"), "w"))

    m[3] = triangle()
    json.dump({"size": [H, W], "polygons": [[10, 90, 60, 20, 110, 90, 10, 90]]},
              open(os.path.join(masks_dir, "mask_03.poly.json"), "w"))

    m[4] = logits_banded(100, 30, 18) > 0.0
    torch.save(torch.from_numpy(logits_banded(100, 30, 18)),
               os.path.join(masks_dir, "mask_04.pt"))

    yy, xx = np.mgrid[0:H, 0:W]
    nd = np.sqrt(((xx - 30) / 24.0) ** 2 + ((yy - 110) / 12.0) ** 2)
    soft = np.zeros((H, W), np.uint8)
    soft[nd <= 0.98] = 240
    soft[(nd > 0.98) & (nd < 1.05)] = 120          # AA band below threshold
    Image.fromarray(soft).save(os.path.join(masks_dir, "mask_05.png"))
    m[5] = soft >= 128

    m[6] = disk(4, 4, 6)
    json.dump({"size": [H, W], "counts": rle_encode(m[6])},
              open(os.path.join(masks_dir, "mask_06.rle.json"), "w"))

    m[7] = donut(64, 64, 22, 9)
    save_png("mask_07.png", m[7])

    pent_full, _ = pentagon(104, 104, 12)
    four = [(104, 92), (115, 100), (111, 114), (97, 114)]
    m[8] = mask_from_polygon([c for p in four for c in p])
    json.dump({"size": [H, W], "polygons": [[c for p in four for c in p]]},
              open(os.path.join(masks_dir, "mask_08.poly.json"), "w"))

    st = star_points(64, 20, 28, 11, ty=-6.0)     # some y < 0 on purpose
    star_flat = [int(round(float(v))) for p in st for v in p]
    m[9] = mask_from_polygon(star_flat)
    json.dump({"size": [H, W], "polygons": [star_flat]},
              open(os.path.join(masks_dir, "mask_09.poly.json"), "w"))

    m[10] = np.zeros((H, W), dtype=bool)          # EMPTY
    json.dump({"size": [H, W], "counts": [H * W]},
              open(os.path.join(masks_dir, "mask_10.rle.json"), "w"))

    m[11] = np.zeros((H, W), dtype=bool)          # EMPTY
    Image.fromarray(np.zeros((H, W), np.uint8)).save(
        os.path.join(masks_dir, "mask_11.png"))

    m[12] = np.zeros((H, W), dtype=bool)          # EMPTY (degenerate poly)
    json.dump({"size": [H, W], "polygons": [[64, 64, 64, 64]]},
              open(os.path.join(masks_dir, "mask_12.poly.json"), "w"))

    m[13] = rect(70, 115, 70, 115)
    np.save(os.path.join(masks_dir, "mask_13.npy"), m[13])

    m[14] = rect(22, 58, 90, 120)
    json.dump({"size": [H, W], "counts": rle_encode(m[14])},
              open(os.path.join(masks_dir, "mask_14.rle.json"), "w"))

    m[15] = pentagon(40, 50, 14)[0]
    pts15 = [(40, 36), (53, 46), (48, 61), (32, 61), (27, 46), (40, 36)]
    json.dump({"size": [H, W], "polygons": [[c for p in pts15 for c in p]]},
              open(os.path.join(masks_dir, "mask_15.poly.json"), "w"))

    m[16] = superellipse(15, 108, 10, 8)
    save_png("mask_16.png", m[16])

    lg17 = np.maximum(logits_banded(90, 80, 14), logits_banded(78, 92, 10))
    m[17] = lg17 > 0.0
    torch.save(torch.from_numpy(lg17), os.path.join(masks_dir, "mask_17.pt"))

    m[18] = np.zeros((H, W), dtype=bool)          # EMPTY
    torch.save(torch.full((H, W), -5.0, dtype=torch.float32),
               os.path.join(masks_dir, "mask_18.pt"))

    m[19] = disk(118, 40, 10)
    json.dump({"size": [64, 128],                    # WRONG declared size
               "counts": rle_encode(m[19])},
              open(os.path.join(masks_dir, "mask_19.rle.json"), "w"))

    m[20] = disk(60, 110, 12)
    json.dump({"size": [H, W], "pixels": m[20].ravel().astype(np.uint8).tolist()},
              open(os.path.join(masks_dir, "mask_20.vrle.json"), "w"))

    cats = ["square", "rect", "triangle", "circle", "ellipse", "blob",
            "ring", "pentagon", "star"]
    instances = [
        {"id": 1,  "file": "masks/mask_01.png",         "category": "square",   "iscrowd": False},
        {"id": 2,  "file": "masks/mask_02.vrle.json",   "category": "rect",     "iscrowd": False},
        {"id": 3,  "file": "masks/mask_03.poly.json",   "category": "triangle", "iscrowd": False},
        {"id": 4,  "file": "masks/mask_04.pt",          "category": "circle",   "iscrowd": False},
        {"id": 5,  "file": "masks/mask_05.png",         "category": "ellipse",  "iscrowd": False},
        {"id": 6,  "file": "masks/mask_06.rle.json",    "category": "blob",     "iscrowd": False},
        {"id": 7,  "file": "masks/mask_07.png",         "category": "ring",     "iscrowd": True},
        {"id": 8,  "file": "masks/mask_08.poly.json",   "category": "pentagon", "iscrowd": False},
        {"id": 9,  "file": "masks/mask_09.poly.json",   "category": "star",     "iscrowd": False},
        {"id": 10, "file": "masks/mask_10.rle.json",    "category": "rect",     "iscrowd": False},
        {"id": 11, "file": "masks/mask_11.png",         "category": "triangle", "iscrowd": False},
        {"id": 12, "file": "masks/mask_12.poly.json",   "category": "circle",   "iscrowd": False},
        {"id": 13, "file": "masks/mask_13.npy",         "category": "square",   "iscrowd": False},
        {"id": 14, "file": "masks/mask_14.rle.json",    "category": "square",   "iscrowd": False},
        {"id": 15, "file": "masks/mask_15.poly.json",   "category": "pentagon", "iscrowd": False},
        {"id": 16, "file": "masks/mask_16.png",         "category": "ellipse",  "iscrowd": False},
        {"id": 17, "file": "masks/mask_17.pt",          "category": "blob",     "iscrowd": False},
        {"id": 18, "file": "masks/mask_18.pt",          "category": "blob",     "iscrowd": False},
        {"id": 19, "file": "masks/mask_19.rle.json",    "category": "ring",     "iscrowd": False},
        {"id": 20, "file": "masks/mask_20.vrle.json",   "category": "blob",     "iscrowd": True},
    ]
    json.dump({"width": W, "height": H, "instances": instances},
              open(os.path.join(out, "meta.json"), "w"), indent=2)
    print("fixtures written to", out)


if __name__ == "__main__":
    build(sys.argv[1])