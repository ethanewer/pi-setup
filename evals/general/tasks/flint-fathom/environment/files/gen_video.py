#!/usr/bin/env python3
"""Synthetic single-jump monocular clip generator (build-time only).

Paints a fixed scene: a flat running track (ground strip) with one bright
"athlete" block resting on it. For a chosen interval the block clearly leaves
the ground (takeoff .. landing); otherwise it rests at a constant baseline row.

NOT part of the graded deliverables. Removed from /app after the build step.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile

import cv2
import numpy as np

W, H = 320, 240
GROUND_ROW = 200                # first pixel row of the ground strip
OBJ_H = 30                      # athlete height (pixels)
OBJ_X0 = 150                    # athlete left edge
OBJ_W = 40                      # athlete width
BG = (30, 34, 92)               # dark-blue sky
STRIP = (78, 52, 26)            # brown track strip
OBJ = (255, 242, 88)             # bright "athlete" color


def offset_at(f, takeoff, landing, peak):
    """Vertical clearance of the subject's bottom at frame f (0 == on ground)."""
    if takeoff is None:
        return 0
    if f < takeoff:
        return 0
    if landing is None:                      # leaves and never comes back
        return peak if f >= takeoff else 0
    if f > landing:
        return 0
    if landing <= takeoff:
        return peak
    span = float(landing - takeoff)
    t = (f - takeoff) / span
    v = peak * (1 - abs(2 * t - 1))
    return max(3, int(round(v)))             # in-flight clearance >= 3 px


def frame_img(f, takeoff, landing, peak):
    img = np.full((H, W, 3), BG, dtype=np.uint8)
    img[GROUND_ROW:, :, :] = STRIP
    off = offset_at(f, takeoff, landing, peak)
    bottom = GROUND_ROW - 1 - off
    top = bottom - (OBJ_H - 1)
    top = max(0, top)
    x_end = min(W, OBJ_X0 + OBJ_W)
    img[top:bottom + 1, OBJ_X0:x_end, :] = OBJ
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--total", type=int, required=True)
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--takeoff", type=int, default=None)
    ap.add_argument("--land", type=int, default=None)
    ap.add_argument("--peak", type=int, default=24)
    args = ap.parse_args()

    with tempfile.TemporaryDirectory() as td:
        for f in range(args.total):
            cv2.imwrite(os.path.join(td, f"f{f:05d}.png"),
                        frame_img(f, args.takeoff, args.land, args.peak))
        cmd = [
            "ffmpeg", "-y", "-framerate", str(args.fps),
            "-i", os.path.join(td, "f%05d.png"),
            "-c:v", "mpeg4", "-q:v", "2", "-pix_fmt", "yuv420p",
            args.out,
        ]
        subprocess.check_call(cmd, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL)

    print(json.dumps({"takeoff": args.takeoff, "landing": args.land,
                      "total": args.total}))
    return 0


if __name__ == "__main__":
    sys.exit(main())