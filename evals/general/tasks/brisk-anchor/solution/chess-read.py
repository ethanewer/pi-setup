#!/usr/bin/env python3
"""chess-read.py — decode a rendered 640x720 board PNG into a structured legal
position: an 8x8 piece placement (8 ranks, '.' = empty, uppercase = white,
lowercase = black) plus the side to move ('w'/'b').

Rendering contract (from the task): board occupies x in [0,640), y in [70,710);
each cell is 80px, cell (r,c) centred at (c*80+40, 70+r*80+40). Square colour is
(229,221,197) when (r+c) even else (148,138,84). An occupied square carries the
piece glyph whose fill colour is one of the 12 documented palette colours; an
empty square shows only its square colour. A side-to-move indicator disc
(radius 16, centre (320,34)) is bright for 'w' and dark for 'b'.

Usage: python3 /app/chess-read.py [input_dir] [output_json]
Defaults: input /app/boards , output /app/positions.json
"""
import json, math, os, sys
from PIL import Image

CELL = 80
BOARD_Y = 70
SIDE_X, SIDE_Y = 320, 34

SQ_L = (229, 221, 197)
SQ_D = (148, 138, 84)
PALETTE = {
    "K": (255, 250, 240), "Q": (188, 232, 255), "R": (255, 214, 214),
    "B": (196, 255, 200), "N": (230, 214, 255), "P": (255, 245, 205),
    "k": (18, 18, 26), "q": (94, 38, 140), "r": (150, 46, 46),
    "b": (42, 122, 88), "n": (28, 92, 168), "p": (168, 118, 32),
}
# centre-of-mass luminance threshold that separates the bright piece colours
BRIGHT_THRESHOLD = 150.0

COLORS = list(PALETTE.items()) + [("_L", SQ_L), ("_D", SQ_D)]

def _d(a, b):
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2

def classify(px):
    best, bd = None, 1e30
    for name, col in COLORS:
        dd = _d(px, col)
        if dd < bd:
            best, bd = name, dd
    return best

def read_board(im):
    # side to move
    r, g, b = im.getpixel((SIDE_X, SIDE_Y))
    side = "w" if (r + g + b) / 3.0 > BRIGHT_THRESHOLD else "b"
    rows = []
    # dense sample over the central core of each square (well away from the
    # square borders and from antialiasing edges); detect piece ink colour
    offs = list(range(-20, 21, 4))      # [-20,-16,...,20] -> 11 x 11 = 121 pts
    for rank in range(8):
        row = ""
        for file in range(8):
            cx = file * CELL + CELL / 2
            cy = BOARD_Y + rank * CELL + CELL / 2
            votes = {}
            for dy in offs:
                for dx in offs:
                    px = im.getpixel((int(cx + dx), int(cy + dy)))
                    cls = classify(px)
                    if cls not in ("_L", "_D"):
                        votes[cls] = votes.get(cls, 0) + 1
            if not votes:
                row += "."
                continue
            # a piece must be backed by a solid run of its ink colour
            piece = max(votes, key=lambda k: (votes[k], 1))
            row += piece if votes[piece] >= 10 else "."
        rows.append(row)
    return rows, side

def decode(path):
    im = Image.open(path).convert("RGB")
    rows, side = read_board(im)
    return {"placement": "".join(rows), "side": side}

def main():
    input_dir = sys.argv[1] if len(sys.argv) > 1 else "/app/boards"
    out_json = sys.argv[2] if len(sys.argv) > 2 else "/app/positions.json"
    results = []
    for n in sorted(os.listdir(input_dir)):
        if not n.lower().endswith((".png", ".jpg", ".jpeg")):
            continue
        rec = decode(os.path.join(input_dir, n))
        results.append({"file": n, "placement": rec["placement"], "side": rec["side"]})
    results = sorted(results, key=lambda r: r["file"])
    with open(out_json, "w") as fh:
        json.dump(results, fh, indent=2)

if __name__ == "__main__":
    main()