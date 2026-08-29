#!/usr/bin/env python3
"""iris-anchor image->board decoder.

Parses a rendered game-board PNG into a set of occupied intersections and their
stone ownership (black/white). Generalizes to any board image that follows the
documented geometry (9x9 intersections, margin=48, cell=48, stone radius=17,
grid line width 3).

Usage: python3 decode_board.py <image.png> -o <out.json>
"""
import cv2
import json
import numpy as np
import sys

MARGIN = 48
CELL = 48
N = 9
ANN_IN = 6      # inner radius of detection annulus (px)
ANN_OUT = 13    # outer radius of detection annulus (px)

# Reference BGR colors of the renderer's palette.
BLACK = np.array([15, 15, 15], dtype=np.float32)     # black stones
WHITE = np.array([245, 245, 245], dtype=np.float32)  # white stones
BG = np.array([215, 220, 242], dtype=np.float32)     # empty wooden board


def decode(path):
    img = cv2.imread(path)
    if img is None:
        raise SystemExit("could not read image: " + path)
    stones = []
    for r in range(N):
        for c in range(N):
            cx = MARGIN + c * CELL
            cy = MARGIN + r * CELL
            samples = []
            for dy in range(-ANN_OUT, ANN_OUT + 1):
                for dx in range(-ANN_OUT, ANN_OUT + 1):
                    d2 = dx * dx + dy * dy
                    if ANN_IN * ANN_IN <= d2 <= ANN_OUT * ANN_OUT:
                        samples.append(img[cy + dy, cx + dx])
            mean = np.mean(samples, axis=0).astype(np.float32)
            db = float(np.linalg.norm(mean - BG))  # bg likely
            dk = float(np.linalg.norm(mean - np.array([15, 15, 15], dtype=np.float32)))
            dw = float(np.linalg.norm(mean - np.array([245, 245, 245], dtype=np.float32)))
            if dk < dw and dk < db:
                stones.append({"r": r, "c": c, "color": "black"})
            elif dw < dk and dw < db:
                stones.append({"r": r, "c": c, "color": "white"})
    return {"n": N, "stones": stones}


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    img_path = sys.argv[1]
    out_path = "board.json"
    for i, a in enumerate(sys.argv):
        if a == "-o":
            out_path = sys.argv[i + 1]
    result = decode(img_path)
    with open(out_path, "w") as fh:
        json.dump(result, fh)
    print(f"decoded {len(result['stones'])} stones -> {out_path}")


if __name__ == "__main__":
    main()