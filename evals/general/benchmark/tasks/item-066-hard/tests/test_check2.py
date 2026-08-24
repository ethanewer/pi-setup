#!/usr/bin/env python3
"""Independent verifier for item-066-hard.

Re-decodes every fixture representation itself (no imports of agent/oracle
code), recomputes kept/dropped sets, masks, bbox/area, crowd RLE, polygon
round-trips, overlap pairs and log expectations.  Prints
`REWARD <fraction>` as its last stdout line.
"""
import json
import os
import re
import sys

import numpy as np
from PIL import Image
import cv2
import torch

SRC = "/app/data"
OUT = "/app/out"
H = W = 128

checks = []


def check(name, ok):
    checks.append((name, bool(ok)))


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
    return rle_decode(d["counts"], (H, W)), d["size"]


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
    return None


def expected_bbox_area(mask):
    ys, xs = np.nonzero(mask)
    x0, y0 = int(xs.min()), int(ys.min())
    w, h = int(xs.max()) - x0 + 1, int(ys.max()) - y0 + 1
    return [x0, y0, w, h], int(mask.sum())


def fill_iou(a, b):
    inter = np.logical_and(a, b).sum()
    union = np.logical_or(a, b).sum()
    return inter / union if union else 0.0


def main():
    try:
        meta = json.load(open(os.path.join(SRC, "meta.json")))
        annotations = json.load(open(os.path.join(OUT, "annotations.json")))
        log = open(os.path.join(OUT, "validation.log")).read()
        check("output files parse", True)
    except Exception:  # noqa: BLE001
        check("output files parse", False)
        print("REWARD 0.0")
        return

    img = annotations.get("images", [{}])[0]
    check("image size 128x128", img.get("width") == W and img.get("height") == H)

    # --- expected masks ----------------------------------------------------
    expected, src_of, declared_of = {}, {}, {}
    for inst in meta["instances"]:
        iid = inst["id"]
        path = os.path.join(SRC, inst["file"])
        name = os.path.basename(path)
        src = srctype_of(name)
        src_of[iid], declared_of[iid] = src, None
        if src is None:
            check(f"fixture decode id {iid}", False)
            continue
        try:
            if src == "png":
                mask, decl = decode_png(path), [H, W]
            elif src == "rle":
                mask, decl = decode_rle(path)
            elif src == "vrle":
                mask, decl = decode_vrle(path)
            elif src == "polygon":
                mask, decl = decode_polygon(path)
            elif src == "logits":
                mask, decl = decode_pt(path)
            else:
                mask, decl = decode_npy(path)
            declared_of[iid] = decl
        except Exception:  # noqa: BLE001
            check(f"fixture decode id {iid}", False)
            continue
        check(f"fixture decode id {iid}", mask.shape == (H, W))
        expected[iid] = {"mask": mask, "cat": inst["category"],
                         "crowd": inst["iscrowd"]}

    expected_ids = set(expected.keys())
    kept = {iid for iid in expected if expected[iid]["mask"].any()}
    dropped = sorted(expected_ids - kept)
    kept_ids = sorted(kept)

    ann_by_id = {a["id"]: a for a in annotations.get("annotations", [])}
    check("annotations ids == kept ids exactly", set(ann_by_id.keys()) == kept)

    cat_map = {c["id"]: c["name"] for c in annotations.get("categories", [])}

    # --- kept instances ----------------------------------------------------
    for iid in kept_ids:
        exp = expected[iid]
        ann = ann_by_id.get(iid)
        if ann is None:
            for nm in ("png", "bbox", "area", "category", "segmentation"):
                check(f"id {iid}: {nm}", False)
            continue
        emask = exp["mask"]
        png = os.path.join(OUT, "masks", f"mask_{iid:02d}.png")
        try:
            amask = decode_png(png)
            check(f"id {iid}: png exists+exact", np.array_equal(emask, amask))
        except Exception:  # noqa: BLE001
            check(f"id {iid}: png exists+exact", False)
        try:
            bbox, area = expected_bbox_area(emask)
            check(f"id {iid}: bbox", ann.get("bbox") == bbox)
            check(f"id {iid}: area", ann.get("area") == area)
        except Exception:  # noqa: BLE001
            check(f"id {iid}: bbox", False)
            check(f"id {iid}: area", False)
        check(f"id {iid}: category", cat_map.get(ann.get("category_id")) == exp["cat"])

        seg = ann.get("segmentation")
        if exp["crowd"]:
            try:
                ok = (isinstance(seg, dict)
                      and seg.get("size") == [H, W]
                      and np.array_equal(emask, rle_decode(seg["counts"], (H, W))))
                check(f"id {iid}: crowd RLE decodes to mask", ok)
            except Exception:  # noqa: BLE001
                check(f"id {iid}: crowd RLE decodes to mask", False)
        else:
            closed_ok, iou_ok = False, False
            try:
                canvas = np.zeros((H, W), np.uint8)
                if isinstance(seg, list) and len(seg) >= 1:
                    closed_ok = True
                    for flat in seg:
                        if not (len(flat) % 2 == 0 and len(flat) >= 6
                                and flat[:2] == flat[-2:]):
                            closed_ok = False
                            break
                    for flat in seg:
                        pts = np.array(flat, dtype=np.float64).reshape(-1, 2).astype(np.int32)
                        cv2.fillPoly(canvas, [pts], 1)
                iou_ok = fill_iou(emask, canvas.astype(bool)) >= 0.995
            except Exception:  # noqa: BLE001
                pass
            check(f"id {iid}: polygon closed+even", closed_ok)
            check(f"id {iid}: polygon fill IoU", iou_ok)

    # --- dropped instances --------------------------------------------------
    for iid in dropped:
        check(f"dropped id {iid}: no annotation", iid not in ann_by_id)
        check(f"dropped id {iid}: no png",
              not os.path.isfile(os.path.join(OUT, "masks", f"mask_{iid:02d}.png")))

    # --- validation log -----------------------------------------------------
    for iid in kept_ids:
        tok = src_of.get(iid, "")
        ok = (re.search(rf"\bid\s+{iid}\b", log) is not None
              and "OK" in log and tok in log)
        check(f"log: kept id {iid} OK line", ok)
    for iid in dropped:
        check(f"log: dropped id {iid} line",
              re.search(rf"\bdrop\b", log) is not None
              and re.search(rf"\bid\s+{iid}\b", log) is not None)
    check("log: size-mismatch for id 19",
          re.search(r"\bsize-mismatch\b", log) is not None
          and re.search(r"\bid\s+19\b", log) is not None)

    # overlap pairs among expected kept masks
    emasks = {iid: expected[iid]["mask"] for iid in kept_ids}
    for a in range(len(kept_ids)):
        for b in range(a + 1, len(kept_ids)):
            ia, ib = kept_ids[a], kept_ids[b]
            if np.logical_and(emasks[ia], emasks[ib]).sum() > 0:
                ok = (re.search(r"\boverlap\b", log) is not None
                      and re.search(rf"\bid\s+{ia}\b", log) is not None
                      and re.search(rf"\bid\s+{ib}\b", log) is not None)
                check(f"log: overlap ({ia},{ib})", ok)

    check("log: no ERROR lines", "ERROR" not in log)

    # --- reward --------------------------------------------------------------
    passed = sum(1 for _, ok in checks if ok)
    total = len(checks)
    reward = round(passed / total, 4) if total else 0.0
    if reward >= 0.9999:
        reward = 1.0
    print(f"checks {passed}/{total} kept={len(kept)} dropped={len(dropped)}", file=sys.stderr)
    print(f"REWARD {reward}")


if __name__ == "__main__":
    main()