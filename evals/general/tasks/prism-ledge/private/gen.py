#!/usr/bin/env python3
"""Fixture generator for prism-ledge. Run inside the task image (torch/PIL)."""
import os, sys, json, shutil, random, math, csv
import numpy as np
from PIL import Image, ImageDraw, ImageFont

SAM_SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sam_model.py")


def render_background(W, H, phrase, seed, text_top, text_height,
                      sky_hi=205, sky_lo=72, track=112, band=196, ink=32):
    rnd = random.Random(seed)
    arr = np.zeros((H, W), dtype=np.uint8)
    sky_rows = max(text_top - 4, 1)
    for y in range(0, sky_rows):
        arr[y, :] = int(sky_hi + (sky_lo - sky_hi) * (y / (sky_rows - 1.0)))
    for y in range(sky_rows, H):
        arr[y, :] = int(track + 3.0 * math.sin(y * 0.4))
    band_top = max(sky_rows, text_top)
    band_bot = min(H, band_top + text_height)
    if band_bot > band_top:
        arr[band_top:band_bot, :] = int(band)
    im = Image.fromarray(arr.astype(np.uint8), "L").copy()
    dr = ImageDraw.Draw(im)
    font = None
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
                 "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"):
        if os.path.exists(path):
            try:
                font = ImageFont.truetype(path, text_height - 4)
                break
            except Exception:
                font = None
    if font is None:
        font = ImageFont.load_default()
    box = dr.textbbox((0, 0), phrase, font=font)
    tw = box[2] - box[0]
    x0 = max(0, (W - tw) // 2)
    dr.text((x0, band_top), phrase, fill=int(ink), font=font)
    arr = np.asarray(im).astype(np.uint8)
    # light deterministic noise below the label band only (kept out of the sky)
    for k in range(rnd.randrange(120, 200)):
        arr[rnd.randrange(band_bot, H), rnd.randrange(0, W)] = rnd.randrange(0, 255)
    return arr


def runner_ellipse(arr, cx, cy, rx, ry, val):
    H, W = arr.shape
    for y in range(max(0, int(cy - ry) - 2), min(H, int(cy + ry) + 3)):
        if abs((y - cy) / ry) > 1.0:
            continue
        for x in range(max(0, int(cx - rx) - 2), min(W, int(cx + rx) + 3)):
            if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                arr[y, x] = val
    return arr


def cells_for(cx, cy, rx, ry, W, H):
    runt = (int(round(cx - rx - 9)), int(round(cy - ry - 7)),
            int(round(cx + rx + 9)), int(round(cy + ry + 7)))
    sky = [(8, 6, min(W - 8, 100), 34),
           (max(8, W - 108), 6, W - 8, 34),
           (max(8, W // 2 - 45), 30, min(W - 8, W // 2 + 75), 58)]
    return [runt] + sky


def build_clip(outdir, W, H, n, phrase, seed, x0, vx, base, rx, ry,
               A, B, lift, text_top, text_height, subject=235):
    os.makedirs(os.path.join(outdir, "frames"), exist_ok=True)
    bg = render_background(W, H, phrase, seed, text_top, text_height)
    frames_dir = os.path.join(outdir, "frames")
    for f in range(n):
        fr = bg.copy()
        cx = x0 + vx * f
        cy = base - (lift if (A <= f <= B) else 0)
        runner_ellipse(fr, cx, cy, rx, ry, subject)
        Image.fromarray(fr, "L").save(os.path.join(frames_dir, "%03d.png" % f))
    Image.fromarray(bg, "L").save(os.path.join(outdir, "background.png"))
    cxA = x0 + vx * A
    cyA = base - lift
    cells = cells_for(cxA, cyA, rx, ry, W, H)
    _write_sam(outdir, bg)
    _write_manifest(outdir, cells)
    return dict(W=W, H=H, n=n, phrase=phrase, x0=x0, vx=vx, base=base, rx=rx,
                ry=ry, A=A, B=B, lift=lift, text_top=text_top,
                text_height=text_height, cells=cells)


def _write_sam(outdir, bg):
    import torch
    b = torch.from_numpy(bg.astype(np.float32) / 255.0).float()
    b = b.unsqueeze(0).unsqueeze(0).contiguous()
    state = {"background": b, "tau": torch.tensor(0.10), "gain": torch.tensor(25.0)}
    torch.save(state, os.path.join(outdir, "sam_weights.pt"))
    shutil.copy(SAM_SRC, os.path.join(outdir, "sam_model.py"))


def _write_manifest(outdir, cells):
    header = ["sample_id", "cell", "x0", "y0", "x1", "y1", "points", "centroid", "tag"]
    with open(os.path.join(outdir, "input.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(header)
        for i, (x0, y0, x1, y1) in enumerate(cells):
            cid = "cell_%d" % i
            w.writerow([cid, cid, x0, y0, x1, y1,
                        "[%d, %d, %d, %d]" % (x0, y0, x1, y1), "[0, 0]", "prompt"])


def main():
    dest = sys.argv[1]
    os.makedirs(dest, exist_ok=True)
    meta = {}
    specs = [
        ("clip_v", {"W": 180, "H": 120, "n": 32, "phrase": "AH7MW2", "x0": 12,
                    "vx": 4, "base": 96, "rx": 14, "ry": 9, "A": 14, "B": 24,
                    "lift": 12, "text_top": 80, "text_height": 18, "seed": 11}),
        ("track_x", {"W": 200, "H": 120, "n": 38, "phrase": "3LV4N2", "x0": 8,
                     "vx": 5, "base": 104, "rx": 16, "ry": 10, "A": 12, "B": 26,
                     "lift": 14, "text_top": 84, "text_height": 20, "seed": 23}),
        ("lane_a", {"W": 160, "H": 116, "n": 28, "phrase": "XV4K7N", "x0": 10,
                    "vx": 4, "base": 92, "rx": 12, "ry": 8, "A": 14, "B": 22,
                    "lift": 11, "text_top": 74, "text_height": 19, "seed": 37}),
        ("bench_y", {"W": 220, "H": 128, "n": 44, "phrase": "H7Z2W4", "x0": 6,
                     "vx": 4, "base": 106, "rx": 17, "ry": 11, "A": 16, "B": 34,
                     "lift": 15, "text_top": 86, "text_height": 22, "seed": 51}),
    ]
    for name, p in specs:
        info = build_clip(os.path.join(dest, name), p["W"], p["H"], p["n"],
                          p["phrase"], None, p["x0"], p["vx"], p["base"],
                          p["rx"], p["ry"], p["A"], p["B"], p["lift"],
                          p["text_top"], p["text_height"], subject=235)
        meta[name] = info
    json.dump(meta, open(os.path.join(dest, "_meta.json"), "w"), indent=2)
    print("generated", sorted(meta.keys()))


if __name__ == "__main__":
    main()