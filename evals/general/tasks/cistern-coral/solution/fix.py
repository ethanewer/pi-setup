#!/usr/bin/env python3
"""Oracle fix for cistern-coral.

Applies the minimal, upstream-shaped repair to the real libvips source in
/app/src/libvips/draw/draw_flood.c: reject a flood-fill whose start point
(x, y) lies at or past the image's right/bottom edge with an explicit
"start point out of image" error before any fill work happens. This script
edits the clone; it never reads /tests.
"""
import sys

PATH = "/app/src/libvips/draw/draw_flood.c"

src = open(PATH, encoding="utf-8").read()

# The fix's anchor: the first flood setup line, straight after the input
# checks in vips_draw_flood_build(). The check is inserted just before it,
# exactly where the upstream fix puts it.
anchor = "\tflood.test = drawflood->test;\n"

addition = (
    "\tif (drawflood->x >= draw->image->Xsize ||\n"
    "\t\tdrawflood->y >= draw->image->Ysize) {\n"
    "\t\tvips_error(class->nickname,\n"
    "\t\t\t\"%s\", _(\"start point out of image\"));\n"
    "\t\treturn -1;\n"
    "\t}\n"
    "\n"
)

if "start point out of image" in src:
    print("oracle: bounds check already present in draw_flood.c", file=sys.stderr)
    sys.exit(1)

n = src.count(anchor)
if n != 1:
    print(f"oracle: expected exactly one anchor line, found {n}",
          file=sys.stderr)
    sys.exit(1)

open(PATH, "w", encoding="utf-8").write(src.replace(anchor, addition + anchor))
print("oracle: added draw_flood start-point bounds check in draw_flood.c")