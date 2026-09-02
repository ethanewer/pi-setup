#!/usr/bin/env python3
"""Deterministic survey-tile fixture generator for the lichen-mesa task.

Generates a tile directory:
  <out>/
    scene.png        8-bit grayscale PNG (the static scene)
    sam_model.py     the distilled TinySAM module for this tile
    sam_weights.pt   per-tile distilled-SAM state_dict (torch.save)
    prompts.csv      rectangular prompt-region manifest (the output schema too)

The generator is deterministic: identical (seed, name, H, W, n_cells) always
yield byte-identical fixtures.
"""
import argparse
import os
import struct
import zlib

import numpy as np
import torch



def write_png(path, arr):
    h, w = arr.shape
    raw = b"".join(b"\x00" + arr[i].tobytes() for i in range(h))

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--height", type=int, default=112)
    ap.add_argument("--width", type=int, default=144)
    args = ap.parse_args()

    rng = np.random.default_rng(args.seed)
    H, W = args.height, args.width
    os.makedirs(args.out, exist_ok=True)

    # ---- background (the model's learned static-scene prior) --------------
    yy, xx = np.mgrid[0:H, 0:W]
    bg = 40.0 + 25.0 * np.sin(np.linspace(0.0, 3.0, H))[:, None] \
        + 18.0 * (xx / W)[None, 0, :] + 12.0 * (yy / H)[0:1, :]
    bg = bg + rng.normal(0.0, 2.0, (H, W))

    # ---- anomalies: smooth bright blobs -----------------------------------
    n_blobs = int(rng.integers(2, 4))
    blobs = []
    for _ in range(n_blobs):
        cy = int(rng.integers(10, H - 10))
        cx = int(rng.integers(10, W - 10))
        ry = int(rng.integers(5, 12))
        rx = int(rng.integers(6, 14))
        amp = float(rng.integers(100, 170)) / 255.0
        blobs.append((cy, cx, ry, rx, amp))

    def add_blob(canvas, blob):
        cy, cx, ry, rx, amp = blob
        d2 = ((yy - cy) / ry) ** 2 + ((xx - cx) / rx) ** 2
        canvas += amp * np.exp(-d2)

    bg_u8 = np.clip(bg + rng.normal(0.0, 1.5, (H, W)), 0, 255)
    scene = np.clip(bg_u8 + sum(
        amp * 255.0 * np.exp(-(((yy - cy) / ry) ** 2 + ((xx - cx) / rx) ** 2))
        for cy, cx, ry, rx, amp in blobs), 0, 255)
    scene_u8 = np.round(scene).astype(np.uint8)

    # ---- model weights: logits ~ c * (image - prior) ----------------------
    a = np.array([0.55, -0.40, 0.30, -0.25])            # stem per-channel gains
    w = np.array([1.0, 1.0, 1.0, 1.0])                  # head per-channel weights
    # logits = sum_i w_i * tanh(a_i * d) ~ (sum_i a_i * w_i) * d for small a_i
    c = float(np.sum(a * w))                            # ~3.0
    bias = -0.02

    prior = bg_u8.astype(np.float32) / 255.0
    stem_w = np.zeros((4, 1, 1, 1), dtype=np.float32)
    stem_w[:, 0, 0, 0] = a.astype(np.float32)
    head_w = np.zeros((1, 4, 1, 1), dtype=np.float32)
    head_w[0, :, 0, 0] = w.astype(np.float32)

    state = {
        "prior": torch.from_numpy(prior[None, None]).float(),
        "stem.weight": torch.from_numpy(stem_w),
        "head.weight": torch.from_numpy(head_w),
        "head.bias": torch.tensor([bias], dtype=torch.float32),
    }
    torch.save(state, os.path.join(args.out, "sam_weights.pt"))

    model_src = f'''"""Distilled MobileSAM-style segmenter pinned to tile {args.name}.

Forward semantics: `image` is a (B, 1, H, W) float tensor normalised to [0, 1]
(uint8 gray / 255).  The output is raw logits; the foreground mask is
sigmoid(forward(image)) > 0.5  and selects exactly the anomalous pixels of the
scene.  Run on CPU: torch.load(..., map_location="cpu"), load_state_dict,
model.eval(), torch.no_grad().
"""
import torch
import torch.nn as nn


class TinySAM(nn.Module):
    def __init__(self, height, width):
        super().__init__()
        self.prior = nn.Parameter(torch.zeros(1, 1, height, width),
                                  requires_grad=False)
        self.stem = nn.Conv2d(1, 4, kernel_size=1, bias=False)
        self.head = nn.Conv2d(4, 1, kernel_size=1, bias=True)

    def forward(self, image):
        d = image - self.prior
        return self.head(torch.tanh(self.stem(d)))
'''
    with open(os.path.join(args.out, "sam_model.py"), "w") as fh:
        fh.write(model_src)

    write_png(os.path.join(args.out, "scene.png"), scene_u8)

    # ---- prompt rectangles -------------------------------------------------
    fg = np.abs(scene - bg_u8) > 38.0  # approximately the anomalous pixels
    cells = []

    def put(x0, y0, x1, y1):
        cells.append([int(x0), int(y0), int(x1), int(y1)])

    # one cell fully containing each blob
    for cy, cx, ry, rx, amp in blobs:
        put(max(0, cx - rx - 3), max(0, cy - ry - 3),
            min(W - 1, cx + rx + 3), min(H - 1, cy + ry + 3))
    # one clipping cell per blob (cuts through the blob)
    for cy, cx, ry, rx, amp in blobs[:2]:
        put(max(0, cx - rx // 2), max(0, cy - ry - 2),
            min(W - 1, cx + rx // 2), min(H - 1, cy + ry // 2))
    # two background-only cells
    for _ in range(2):
        cw = int(rng.integers(6, 12))
        ch = int(rng.integers(6, 12))
        x0 = int(rng.integers(0, W - cw))
        y0 = int(rng.integers(0, H - ch))
        if fg[y0:y0 + ch, x0:x0 + cw].any():
            # nudge to a quiet corner instead
            put(W - cw - 2, H - ch - 2, W - 2, H - 2)
        else:
            put(x0, y0, x0 + cw, y0 + ch)

    with open(os.path.join(args.out, "prompts.csv"), "w", newline="") as fh:
        fh.write("cell_id,x0,y0,x1,y1\n")
        for i, (x0, y0, x1, y1) in enumerate(cells):
            fh.write("q%02d,%d,%d,%d,%d\n" % (i, x0, y0, x1, y1))

    print("tile %s: %dx%d, %d blobs, %d cells -> %s"
          % (args.name, W, H, len(blobs), len(cells), args.out))


if __name__ == "__main__":
    main()
