#!/usr/bin/env python3
"""Independent reference verifier for prism-ledge.

Computes ground-truth values from the clip's own pixels (frames + background) by
an implementation that does NOT reuse the solution's pipeline code, then checks
the agent's out.csv / analysis.json / cdecode against them.

Usage:
  verify.py <clip_dir> <out_csv> <analysis_json> <expected_phrase> [cdecode]

Exit 0 when every competency check passes, else 1 (prints the failing reasons).
"""
import os, sys, json, csv, ast, subprocess
import numpy as np
import cv2

THR = 30.0          # abs(frame-background) foreground threshold for reference
CDECODE, LATEX = None, None

def gray_pil_or_cv2(path):
    return cv2.imread(path, cv2.IMREAD_GRAYSCALE)


def ref_foreground(bg, frame):
    return (np.abs(frame.astype(np.int16) - bg.astype(np.int16)) > THR)


def bbox(mask):
    ys, xs = np.where(mask)
    if xs.size == 0:
        return None
    return (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))


def iou_boxes(a, b):
    ax0, ay0, ax1, ay1 = a
    bx0, by0, bx1, by1 = b
    ix0, iy0 = max(ax0, bx0), max(ay0, by0)
    ix1, iy1 = min(ax1, bx1), min(ay1, by1)
    iw, ih = max(0, ix1 - ix0 + 1), max(0, iy1 - iy0 + 1)
    inter = iw * ih
    ua = (ax1 - ax0 + 1) * (ay1 - ay0 + 1) + (bx1 - bx0 + 1) * (by1 - by0 + 1) - inter
    return inter / ua if ua else 0.0


def events_from(bg, frames):
    n = len(frames)
    cents = []
    for f in range(n):
        fg = ref_foreground(bg, frames[f])
        ys, xs = np.where(fg)
        if xs.size:
            cents.append(float(ys.mean()))
        else:
            cents.append(float('nan'))
    cy = [c for c in cents if not np.isnan(c)]
    baseline = float(np.median(cy)) if cy else 0.0
    lift = [baseline - c if not np.isnan(c) else 0.0 for c in cents]
    air = [f for f in range(n) if lift[f] > 3.0]
    return baseline, (air[0] if air else -1), (air[-1] if air else -1), cents


def build_mask_from_points(points, w, h):
    """points: flat [x0,y0,x1,y1,...]; returns HxW bool local mask."""
    pts = []
    for i in range(0, len(points), 2):
        pts.append([points[i], points[i + 1]])
    if len(pts) < 3:
        return np.zeros((h, w), dtype=bool)
    poly = np.array(pts, dtype=np.int32).reshape(-1, 1, 2).clip(0, None)
    m = np.zeros((h + 2, w + 2), dtype=np.uint8)
    cv2.fillPoly(m, [poly], 1)
    return m[:h, :w].astype(bool)


def main():
    global CDECODE
    clip, out_csv, ana_json, phrase = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    cdecode = sys.argv[5] if len(sys.argv) > 5 else "/app/cdecode"
    fails = []

    bg = gray_pil_or_cv2(os.path.join(clip, "background.png"))
    H, W = bg.shape
    frames_dir = os.path.join(clip, "frames")
    frames = sorted(f for f in os.listdir(frames_dir) if f.endswith(".png"))
    frames_imgs = [gray_pil_or_cv2(os.path.join(frames_dir, f)) for f in frames]
    N = len(frames_imgs)

    # --- C-14: cdecode reproduces the reference pixel matrix -----------------
    for probe in [os.path.join(clip, "background.png"), os.path.join(frames_dir, frames[0])]:
        r = subprocess.run([cdecode, probe], capture_output=True, text=True)
        if r.returncode != 0:
            fails.append("cdecode exited %d on %s" % (r.returncode, probe))
            continue
        got = np.array([list(map(int, ln.split()))
                        for ln in r.stdout.splitlines() if ln.strip()],
                       dtype=np.uint8)
        ref = gray_pil_or_cv2(probe)
        if got.shape != ref.shape or not np.array_equal(got, ref):
            fails.append("cdecode matrix mismatch on %s" % probe)

    # --- read agent outputs ------------------------------------------------
    with open(ana_json) as fh:
        ana = json.load(fh)
    with open(os.path.join(clip, "input.csv")) as fh:
        in_rows = list(csv.DictReader(fh))
        in_header = list(in_rows[0].keys()) if in_rows else None
    with open(out_csv) as fh:
        orows = list(csv.DictReader(fh))
        o_header = list(orows[0].keys()) if orows else None

    # --- schema (C-b2): same header + row count, list-valued flat numbers ----
    if in_header != o_header:
        fails.append("schema headers differ: %s" % (o_header,))
    if len(orows) != len(in_rows):
        fails.append("row count: agent %d vs input %d" % (len(orows), len(in_rows)))
    for col in ("points", "centroid"):
        if col not in (o_header or []):
            fails.append("missing list column %s" % col)
            continue
        for row in orows:
            try:
                v = ast.literal_eval(row[col])
            except Exception:
                fails.append("column %s not a literal list" % col)
                continue
            if not isinstance(v, list) or not all(isinstance(t, (int, float)) for t in v):
                fails.append("column %s is not a flat numeric list" % col)

    # --- events + tracking (C-2a, C-9d0) -----------------------------------
    base_ref, to_ref, ld_ref, cents_ref = events_from(bg, frames_imgs)
    ag_to, ag_ld = ana.get("takeoff_frame", -1), ana.get("landing_frame", -1)
    if abs(int(ag_to) - to_ref) > 1 or abs(int(ag_ld) - ld_ref) > 1:
        fails.append("event mismatch agent(%s,%s) ref(%s,%s)"
                     % (ag_to, ag_ld, to_ref, ld_ref))
    agboxes = ana.get("bboxes", [])
    if len(agboxes) != N:
        fails.append("bbox count %d != frames %d" % (len(agboxes), N))
    else:
        good = 0; tot = 0
        for f in range(N):
            fg = ref_foreground(bg, frames_imgs[f])
            rb = bbox(fg)
            if rb is None:
                continue
            tot += 1
            ab = agboxes[f]
            if ab and iou_boxes(tuple(ab), rb) > 0.80:
                good += 1
        if tot and good < 0.85 * tot:
            fails.append("bbox tracking too weak %d/%d" % (good, tot))

    # --- OCR (C-be7) --------------------------------------------------------
    ocr = ana.get("ocr_text", "")
    if ocr.strip().upper() != phrase.strip().upper():
        fails.append("OCR mismatch agent=%r expected=%r" % (ocr, phrase))

    # --- per-cell masks + geometry (C-7a6, C-6d8) --------------------------
    ref_frame = to_ref if to_ref >= 0 else N - 1
    ref_fg = ref_foreground(bg, frames_imgs[ref_frame])
    for row in orows:
        x0, y0, x1, y1 = (int(row[c]) for c in ("x0", "y0", "x1", "y1"))
        ref_local = ref_fg[y0:y1 + 1, x0:x1 + 1]
        try:
            pts = ast.literal_eval(row["points"])
        except Exception:
            pts = None
        cw, ch = x1 - x0 + 1, y1 - y0 + 1
        if ref_local.sum() == 0:
            if pts not in ([], None):
                fails.append("cell %s expected empty but had poly" % row["cell"])
            continue
        # non-empty cell: geometry invariants
        if not isinstance(pts, list) or len(pts) < 8:
            fails.append("cell %s poly too small" % row["cell"])
            continue
        ag_mask = build_mask_from_points(pts, cw, ch)
        inter = np.logical_and(ag_mask, ref_local).sum()
        union = np.logical_or(ag_mask, ref_local).sum()
        if union and inter / float(union) < 0.6:
            fails.append("cell %s mask IoU %.2f" % (row["cell"], inter / float(union)))
        if ag_mask.sum() > 0.99 * cw * ch:
            fails.append("cell %s poly is the full prompt rectangle" % row["cell"])
        # must be a genuine interior/polygon (not exactly the 4 corners)
        if ag_mask.sum() < 4:
            fails.append("cell %s poly degenerate" % row["cell"])
        # single connected component in the reference (ellipse chip)
        ncc, _ = cv2.connectedComponents(ref_local.astype(np.uint8))
        if ncc - 1 > 1:
            fails.append("cell %s reference not single-connected" % row["cell"])

    # --- non-overlap (C-6d8): cells are disjoint rectangles, so masks are    --
    # disjoint by construction; nothing further to check beyond the rect bounds.
    # (polys are clipped to their own cell, so no two can intersect.)

    if fails:
        print("FAIL:\n  " + "\n  ".join(fails))
        return 1
    print("PASS clip=%s frames=%d events(%d,%d) ocr=%s cells=%d"
          % (os.path.basename(clip), N, to_ref, ld_ref, phrase, len(orows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())