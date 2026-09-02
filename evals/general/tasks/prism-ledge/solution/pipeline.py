#!/usr/bin/env python3
"""pipeline.py — the prism-ledge vision pipeline (deliverable).

Given a clip bundle and an output directory it:
  1. Loads the distilled same-any-style checkpoint shipped with the clip and runs
     CPU inference to obtain the moving-subject foreground at every frame.
  2. Tracks the subject's bounding extent per frame (background subtraction /
     frame differencing) and infers takeoff/landing instants from the vertical
     motion of the tracked object.
  3. Drives the prompt operator over each reference rectangle to produce a
     single contiguous, mutually disjoint, non-trivial polyline per cell.
  4. Recovers and OCRs the printed label painted on the track.
  5. Writes out.csv (same schema/row count as the input manifest, coordinates as
     list-valued fields) and analysis.json with the tracked/event/ocr results.

Usage:  pipeline.py <clip_dir> <out_dir>
"""
import os, sys, json, csv, re, subprocess, importlib.util
import numpy as np
import cv2
import torch
import pytesseract

CDECODE = "/app/cdecode"
OCR_WHITELIST = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"


# --------------------------------------------------------------------------- #
# 1. C raster decode (the classifier's matrix source)
# --------------------------------------------------------------------------- #
def decode_png(path):
    """Return the HxW uint8 grayscale matrix by invoking /app/cdecode."""
    r = subprocess.run([CDECODE, path], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("cdecode failed on %s: %s" % (path, r.stderr[:400]))
    rows = [list(map(int, ln.split()))
            for ln in r.stdout.splitlines() if ln.strip()]
    return np.asarray(rows, dtype=np.uint8)


# --------------------------------------------------------------------------- #
# 2. Load the distilled SAM checkpoint and run CPU inference
# --------------------------------------------------------------------------- #
def load_model(clip_dir, bg):
    spec = importlib.util.spec_from_file_location(
        "sam_clip_model", os.path.join(clip_dir, "sam_model.py"))
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    H, W = bg.shape
    model = mod.TinySAM(H, W)
    state = torch.load(os.path.join(clip_dir, "sam_weights.pt"),
                       map_location="cpu")
    model.load_state_dict(state)
    model.eval()
    return model


# --------------------------------------------------------------------------- #
# 3. Tracker: frame differencing -> bbox; vertical motion -> events
# --------------------------------------------------------------------------- #
def tracked_analysis(masks):
    N = masks.shape[0]
    bboxes, cents = [], []
    for f in range(N):
        ys, xs = np.where(masks[f])
        if xs.size == 0:
            bboxes.append([])
            cents.append([float('nan'), float('nan')])
            continue
        bboxes.append([int(xs.min()), int(ys.min()),
                       int(xs.max()), int(ys.max())])
        cents.append([float(xs.mean()), float(ys.mean())])
    cy = [c[1] for c in cents if not np.isnan(c[1])]
    baseline = float(np.median(cy)) if cy else 0.0
    lift = [0.0] * N
    for f in range(N):
        if not np.isnan(cents[f][1]):
            lift[f] = baseline - cents[f][1]
    airborne = [f for f in range(N) if lift[f] > 3.0]
    takeoff = airborne[0] if airborne else -1
    landing = airborne[-1] if airborne else -1
    return bboxes, cents, baseline, takeoff, landing


# --------------------------------------------------------------------------- #
# 4. Per-cell polyline normalisation (single, non-overlapping, non-trivial)
# --------------------------------------------------------------------------- #
def cell_polyline(cell_mask):
    """Return flattened [x0,y0,x1,y1,...] polyline for a binary cell mask."""
    if cell_mask.sum() == 0:
        return []
    m = cell_mask.astype(np.uint8)
    cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not cnts:
        return []
    cnt = max(cnts, key=cv2.contourArea)
    poly = cv2.approxPolyDP(cnt, 1.0, True)
    pts = poly.reshape(-1, 2).astype(float)
    flat = []
    for x, y in pts:
        flat.append(round(float(x), 2))
        flat.append(round(float(y), 2))
    return flat


# --------------------------------------------------------------------------- #
# 5. OCR of the printed label on the track
# --------------------------------------------------------------------------- #
def ocr_phrase(bg):
    H, W = bg.shape
    lo = H // 2
    rowmean = bg[lo:, :].mean(axis=1)
    # widen a sharp plateau so the whole bright band is captured
    k = np.ones(5) / 5.0
    sm = np.convolve(rowmean, k, mode='same')
    best = int(np.argmax(sm))
    thr = 0.92 * sm[best]
    ys = np.where(sm >= thr)[0]
    y0b, y1b = max(0, int(ys.min())), min(len(sm) - 1, int(ys.max()))
    band = bg[lo + y0b: lo + y1b + 1, :]
    dark = (band < 90).astype(np.uint8) * 255
    colsum = dark.sum(axis=0)
    xs = np.where(colsum > 0)[0]
    if xs.size == 0:
        return ""
    crop = band[:, max(0, xs.min() - 2): min(W, xs.max() + 3)]
    inv = cv2.bitwise_not(crop)
    big = cv2.resize(inv, None, fx=3, fy=3, interpolation=cv2.INTER_CUBIC)
    _, bw = cv2.threshold(big, 120, 255, cv2.THRESH_BINARY)
    tmp = "/tmp/_pipeline_ocr.png"
    cv2.imwrite(tmp, bw)
    cfg = "--psm 7 -c tessedit_char_whitelist=" + OCR_WHITELIST
    raw = pytesseract.image_to_string(tmp, config=cfg)
    norm = re.sub(r'[^A-Z0-9]', '', raw.upper())
    return norm


# --------------------------------------------------------------------------- #
# 6. write outputs
# --------------------------------------------------------------------------- #
def main():
    if len(sys.argv) < 3:
        print("usage: pipeline.py <clip_dir> <out_dir>")
        return 2
    clip, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)

    bg = decode_png(os.path.join(clip, "background.png"))
    H, W = bg.shape
    frames_dir = os.path.join(clip, "frames")
    frame_files = sorted(f for f in os.listdir(frames_dir) if f.endswith(".png"))
    N = len(frame_files)
    frames = np.stack([decode_png(os.path.join(frames_dir, f)) for f in frame_files])
    frames = frames.astype(np.float32) / 255.0

    model = load_model(clip, bg)
    with torch.no_grad():
        logits = model(torch.from_numpy(frames).unsqueeze(1))
    masks = (torch.sigmoid(logits.squeeze(1)) > 0.5).numpy()   # (N,H,W) bool

    bboxes, cents, baseline, takeoff, landing = tracked_analysis(masks)
    ref_frame = takeoff if takeoff >= 0 else N - 1

    # ---- per-cell prompt loop (the mask operator) -------------------------- #
    with open(os.path.join(clip, "input.csv")) as fh:
        reader = csv.DictReader(fh)
        header = reader.fieldnames
        in_rows = list(reader)

    out_rows = []
    for row in in_rows:
        x0 = int(row["x0"]); y0 = int(row["y0"])
        x1 = int(row["x1"]); y1 = int(row["y1"])
        cell_mask = masks[ref_frame, y0:y1 + 1, x0:x1 + 1]
        poly = cell_polyline(cell_mask)
        if cell_mask.sum() > 0:
            ys, xs = np.where(cell_mask)
            cent = [round(float(xs.mean()), 2), round(float(ys.mean()), 2)]
        else:
            cent = []
        row["points"] = repr(poly)
        row["centroid"] = repr(cent)
        out_rows.append(row)

    with open(os.path.join(out, "out.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(header)
        for row in out_rows:
            w.writerow([row[h] for h in header])

    ocr = ocr_phrase(bg)
    analysis = {
        "clip": os.path.basename(clip),
        "n_frames": N,
        "height": H, "width": W,
        "bboxes": bboxes,
        "centroids": cents,
        "baseline_y": round(baseline, 2),
        "takeoff_frame": takeoff,
        "landing_frame": landing,
        "ocr_text": ocr,
    }
    with open(os.path.join(out, "analysis.json"), "w") as fh:
        json.dump(analysis, fh)
    return 0


if __name__ == "__main__":
    sys.exit(main())