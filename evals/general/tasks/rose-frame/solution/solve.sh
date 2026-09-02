#!/bin/bash
set -eu

# Real oracle: write the renderer program, then run it on the provided scene to
# produce the output. It never reads /tests and has no precomputed answers.

cat > /app/render.py <<'PY'
#!/usr/bin/env python3
"""Render a procedural scene described by scene.json into a P6 PPM image.

Usage: python3 render.py <scene.json> <output.ppm>

Scene format (all coordinates are integers in units of one pixel, the canvas
origin is the top-left pixel at (0,0), and the primitives list is in painter
order so that later entries are drawn on top of earlier ones):

{
  "width": <int>, "height": <int>,
  "background": [r, g, b],
  "primitives": [
    {"type": "rect",   "x": int, "y": int, "w": int, "h": int, "color": [r,g,b]},
    {"type": "circle", "cx": float, "cy": float, "r": float, "color": [r,g,b]},
    {"type": "hline",  "y": int, "x0": int, "x1": int, "color": [r,g,b]},
    {"type": "vline",  "x": int, "y0": int, "y1": int, "color": [r,g,b]}
  ]
}

Semantics
- The canvas is initialized to ``background``.
- ``rect`` fills the inclusive integer span [x, x+w-1] x [y, y+h-1].
- ``circle`` fills every pixel whose center (px+0.5, py+0.5) satisfies
  (px+0.5 - cx)^2 + (py+0.5 - cy)^2 <= r^2.  A circle with r <= 0 draws nothing.
- ``hline``/``vline`` draw one-pixel-wide lines with inclusive endpoints (x0..x1
  or y0..y1); the endpoints may be given in either order.
- Geometry is clipped to the canvas: any pixels outside [0,width)x[0,height)
  are ignored and must NOT affect the image.  Shapes may be entirely outside
  the canvas (they simply draw nothing).  A rect with w == 0 or h == 0 draws
  nothing.
- Colors are already in [0, 255]; clamps for safety only.

Output: raw P6 binary PPM with header
  "P6\n<width> <height>\n255\n"
followed by height*width RGB triples in row-major order (top row first).
"""
import json
import sys


def clamp(v):
    return max(0, min(255, int(round(v))))


def render(scene):
    w = int(scene["width"]); h = int(scene["height"])
    bg = [clamp(c) for c in scene["background"]]
    canvas = [list(bg) for _ in range(w * h)]

    def fill(x, y, col):
        if 0 <= x < w and 0 <= y < h:
            canvas[y * w + x] = [clamp(col[0]), clamp(col[1]), clamp(col[2])]

    for p in scene.get("primitives", []):
        t = p["type"]; col = p["color"]
        if t == "rect":
            x0, y0, ww, hh = int(p["x"]), int(p["y"]), int(p["w"]), int(p["h"])
            for yy in range(y0, y0 + hh):
                for xx in range(x0, x0 + ww):
                    fill(xx, yy, col)
        elif t == "hline":
            y = int(p["y"]); a, b = int(p["x0"]), int(p["x1"])
            if a > b:
                a, b = b, a
            for xx in range(a, b + 1):
                fill(xx, y, col)
        elif t == "vline":
            x = int(p["x"]); a, b = int(p["y0"]), int(p["y1"])
            if a > b:
                a, b = b, a
            for yy in range(a, b + 1):
                fill(x, yy, col)
        elif t == "circle":
            cx, cy, r = float(p["cx"]), float(p["cy"]), float(p["r"])
            if r <= 0:
                continue
            xmin = max(0, int(cx - r) - 1); xmax = min(w - 1, int(cx + r) + 1)
            ymin = max(0, int(cy - r) - 1); ymax = min(h - 1, int(cy + r) + 1)
            for yy in range(ymin, ymax + 1):
                for xx in range(xmin, xmax + 1):
                    if (xx + 0.5 - cx) ** 2 + (yy + 0.5 - cy) ** 2 <= r * r:
                        fill(xx, yy, col)
        else:
            raise ValueError("unknown primitive: %r" % (t,))
    return w, h, canvas


def to_ppm(w, h, canvas):
    head = ("P6\n%d %d\n255\n" % (w, h)).encode()
    body = bytearray()
    for y in range(h):
        for x in range(w):
            body += bytes(canvas[y * w + x])
    return head + bytes(body)


if __name__ == "__main__":
    scenepath, outpath = sys.argv[1], sys.argv[2]
    with open(scenepath) as f:
        scene = json.load(f)
    w, h, canvas = render(scene)
    with open(outpath, "wb") as f:
        f.write(to_ppm(w, h, canvas))
PY

# Do the actual work: render the shipped scene to produce the output artifact.
python3 /app/render.py /app/scene.json /app/output.ppm

echo "solve done"