import argparse
import re
import sys

def read_ppm(path):
    with open(path, "rb") as f:
        data = f.read()
    m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+(\d+)\s", data)
    if not m:
        raise ValueError("not a P6 PPM")
    w, h, mx = int(m.group(1)), int(m.group(2)), int(m.group(3))
    body = data[m.end():]
    if len(body) != w * h * 3:
        raise ValueError(f"body {len(body)} != {w*h*3}")
    return w, h, body

ap = argparse.ArgumentParser()
ap.add_argument("a")
ap.add_argument("b")
args = ap.parse_args()

wa, ha, ba = read_ppm(args.a)
wb, hb, bb = read_ppm(args.b)
if (wa, ha) != (wb, hb):
    print(f"SIZE MISMATCH {wa}x{ha} vs {wb}x{hb}")
    sys.exit(1)
diff = sum(1 for x, y in zip(ba, bb) if x != y)
print(f"bytes differ: {diff}/{len(ba)} ({100.0*diff/max(1,len(ba)):.3f}%)")
sys.exit(0 if diff == 0 else 1)