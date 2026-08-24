#!/usr/bin/env python3
"""Independent verifier for item-066-main.

Re-decodes each fixture representation itself (no imports of agent/oracle code)
and compares the agent's /app/out artifacts pixel-for-pixel.  Prints
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
H = W = 96
IDS = [1, 2, 3, 4, 5, 6]

checks = []  # (name, bool)


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
    return rle_decode(d["counts"], tuple(d["size"])), tuple(d["size"])


def decode_polygon(path):
    d = json.load(open(path))
    size = tuple(d["size"])
    canvas = np.zeros(size, np.uint8)
    for flat in d["polygons"]:
        if len(flat) % 2 != 0 or len(flat) < 4:
            continue
        pts = np.round(np.array(flat, dtype=np.float64).reshape(-1, 2)).astype(np.int32)
        pts = np.clip(pts, 0, [size[1] - 1, size[0] - 1])
        closed = np.vstack([pts, pts[:1]])
        cv2.fillPoly(canvas, [closed], 1)
    return canvas.astype(bool), size


def decode_pt(path):
    t = torch.load(path, map_location="cpu", weights_only=False)
    return t.numpy() > 0, tuple(t.shape)


def decode_npy(path):
    a = np.load(path)
    return a.astype(bool), tuple(a.shape)


def expected_bbox_area(mask):
    ys, xs = np.nonzero(mask)
    x0, y0 = int(xs.min()), int(ys.min())
    w, h = int(xs.max()) - x0 + 1, int(ys.max()) - y0 + 1
    return [x0, y0, w, h], int(mask.sum())


def rle_decode_agent(counts, shape):
    return rle_decode(counts, shape)


def fill_iou(mask_a, mask_b):
    inter = np.logical_and(mask_a, mask_b).sum()
    union = np.logical_or(mask_a, mask_b).sum()
    return inter / union if union else 0.0


def main():
    try:
        meta = json.load(open(os.path.join(SRC, "meta.json")))
        annotations = json.load(open(os.path.join(OUT, "annotations.json")))
        log = open(os.path.join(OUT, "validation.log")).read()
        for i in IDS:
            png = os.path.join(OUT, "masks", f"mask_{i:02d}.png")
            check(f"png exists id {i}", os.path.isfile(png))
    except Exception as exc:  # noqa: BLE001
        check("output files readable", False)
        print("REWARD 0.0")
        return

    # --- expected masks from fixtures -------------------------------------
    expected = {}
    for inst in meta["instances"]:
        iid = inst["id"]
        path = os.path.join(SRC, inst["file"])
        name = os.path.basename(path)
        if name.endswith(".png"):
            mask, _ = decode_png(path), (H, W)
        elif name.endswith(".rle.json"):
            mask, _ = decode_rle(path)
        elif name.endswith(".poly.json"):
            mask, _ = decode_polygon(path)
        elif name.endswith(".pt"):
            mask, _ = decode_pt(path)
        elif name.endswith(".npy"):
            mask, _ = decode_npy(path)
        else:
            check(f"fixture decode id {iid}", False)
            continue
        if mask.shape != (H, W):
            check(f"fixture shape id {iid}", False)
            continue
        expected[iid] = {"mask": mask, "cat": inst["category"],
                         "crowd": inst["iscrowd"], "src": name}

    check("all fixtures decoded", len(expected) == len(meta["instances"]))

    ann_by_id = {}
    for a in annotations.get("annotations", []):
        ann_by_id[a.get("id")] = a

    check("exactly ids 1..6 annotated",
          set(ann_by_id.keys()) == set(IDS))

    cat_map = {c["id"]: c["name"] for c in annotations.get("categories", [])}
    img = annotations.get("images", [{}])[0]
    check("image size 96x96", img.get("width") == W and img.get("height") == H)

    # --- per-instance checks ----------------------------------------------
    for iid in IDS:
        exp = expected.get(iid)
        ann = ann_by_id.get(iid)
        if exp is None or ann is None:
            check(f"id {iid}: present", False)
            continue

        emask = exp["mask"]

        # PNG byte-level robustness: agent PNG must represent the same binary mask
        try:
            amask = decode_png(os.path.join(OUT, "masks", f"mask_{iid:02d}.png"))
            check(f"id {iid}: png mask exact", np.array_equal(emask, amask))
        except Exception:  # noqa: BLE001
            check(f"id {iid}: png mask exact", False)

        try:
            bbox, area = expected_bbox_area(emask)
            check(f"id {iid}: bbox", ann.get("bbox") == bbox)
            check(f"id {iid}: area", ann.get("area") == area)
        except Exception:  # noqa: BLE001
            check(f"id {iid}: bbox", False)
            check(f"id {iid}: area", False)

        # category round-trip
        check(f"id {iid}: category",
              cat_map.get(ann.get("category_id")) == exp["cat"])

        seg = ann.get("segmentation")
        if exp["crowd"]:
            try:
                ok = (isinstance(seg, dict) and seg.get("size") == [H, W]
                      and np.array_equal(
                          emask, rle_decode_agent(seg["counts"], (H, W))))
                check(f"id {iid}: crowd RLE decodes to mask", ok)
            except Exception:  # noqa: BLE001
                check(f"id {iid}: crowd RLE decodes to mask", False)
        else:
            try:
                canvas = np.zeros((H, W), np.uint8)
                ok_shapes = isinstance(seg, list) and len(seg) >= 1
                closed_ok = False
                if ok_shapes:
                    for flat in seg:
                        closed_ok = (len(flat) % 2 == 0 and len(flat) >= 6
                                     and flat[:2] == flat[-2:])
                        if not closed_ok:
                            break
                if ok_shapes:
                    for flat in seg:
                        pts = np.array(flat, dtype=np.float64).reshape(-1, 2).astype(np.int32)
                        cv2.fillPoly(canvas, [pts], 1)
                amask = canvas.astype(bool)
                iou = fill_iou(emask, amask)
                check(f"id {iid}: polygon closed+even", closed_ok)
                check(f"id {iid}: polygon fill IoU", iou >= 0.995)
            except Exception:  # noqa: BLE001
                check(f"id {iid}: polygon closed+even", False)
                check(f"id {iid}: polygon fill IoU", False)

    # --- validation log ---------------------------------------------------
    for iid in IDS:
        m = re.search(r"\bid\s+%d\b[^\n]*OK" % iid, log)
        check(f"log: id {iid} OK line", m is not None)
    check("log: no ERROR lines", "ERROR" not in log)

    # --- reward ------------------------------------------------------------
    passed = sum(1 for _, ok in checks if ok)
    total = len(checks)
    reward = round(passed / total, 4) if total else 0.0
    if reward >= 0.9999:
        reward = 1.0
    print(f"checks {passed}/{total}", file=sys.stderr)
    print(f"REWARD {reward}")


if __name__ == "__main__":
    main()