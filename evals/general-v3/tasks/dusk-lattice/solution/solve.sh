#!/bin/bash
# Oracle for dusk-lattice: write the reverse-engineered reimplementation and
# the findings notes. Never reads /tests.
set -eu

REIMPL="/app/reimpl.py"
NOTES="/app/notes.md"

cat > "$REIMPL" <<'PY'
#!/usr/bin/env python3
"""Reverse-engineered reimplementation of the native scene-postprocessing
codec (see /app/notes.md for the recovered model). Pipeline: parse ASCII P2
PPM (whitespace + '#' comments tolerated) -> rotate the frame 90 degrees
clockwise -> push every channel value through the fixed 8-bit bit-reversal
tone table -> reorder channels (b,g,r) -> emit canonical P2 (single-space
separated, one row per line)."""
import re
import sys


def rev8(v: int) -> int:
    return int("{:08b}".format(v & 0xFF)[::-1], 2)


def parse_ppm(data: str):
    txt = re.sub(r"#[^\n]*", " ", data)
    toks = txt.split()
    if not toks or toks[0] != "P2":
        raise ValueError("bad magic")
    w, h, maxv = int(toks[1]), int(toks[2]), int(toks[3])
    if maxv != 255:
        raise ValueError("unsupported maxval")
    vals = [int(t) for t in toks[4:4 + w * h * 3]]
    if len(vals) != w * h * 3 or any(v < 0 or v > 255 for v in vals):
        raise ValueError("bad pixel data")
    px = [[tuple(vals[((y * w + x) * 3):((y * w + x) * 3) + 3])
           for x in range(w)] for y in range(h)]
    return w, h, px


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: reimpl.py <in.ppm>", file=sys.stderr)
        return 2
    with open(sys.argv[1], "r", encoding="ascii") as fh:
        w, h, px = parse_ppm(fh.read())

    out = ["P2", "%d %d" % (h, w), "255"]
    for rr in range(w):              # result rows    = old width
        row = []
        for cc in range(h):          # result columns = old height
            r, g, b = px[h - 1 - cc][rr]   # 90 deg clockwise
            row += [str(rev8(b)), str(rev8(g)), str(rev8(r))]
        out.append(" ".join(row))
    sys.stdout.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x "$REIMPL"

cat > "$NOTES" <<'MD'
# pixelcast reverse-engineering notes

Method: probed the stripped binary with crafted 1x1 / 2x1 / 1x2 / 3-channel
frames and confirmed the recovered model against `objdump -d` disassembly
(one table-free arithmetic loop, one geometry double loop).

Findings:

1. **Input parsing** — ASCII `P2` PPM. Whitespace-insensitive; `#` starts a
   comment running to end of line and may appear anywhere in the header.
   `maxval` must be 255; pixel values 0..255, three per pixel (R,G,B),
   row-major. Non-zero exit on malformed input.

2. **Geometry** — the frame is rotated **90 degrees clockwise**: a W x H frame
   becomes an H x W frame, and `result(r', c') = original(H-1-c', r')`.
   Verified with 2x1 and 1x2 probes (orientation) and a 3x2 probe (aspect).

3. **Per-channel value transform** — every channel value v is mapped through
   the fixed tone table `T(v) = bit-reverse of v in 8 bits`
   (e.g. T(1)=128, T(127)=254, T(254)=127, T(0)=0, T(255)=255). Recovered by
   sweeping a 1x1 frame across all 256 values; confirmed in disassembly as
   eight rotate/shift steps.

4. **Channel order** — output pixel channels are the input's (b, g, r), i.e.
   the order is reversed after the tone table is applied. Determined with a
   1x1 frame whose three channels were pairwise distinct.

5. **Output serialization** — exactly:
   `P2\n<H> <W>\n255\n` then one line per output row, values (3 per pixel)
   separated by single spaces, newline at the end of every row. No trailing
   spaces, no extra blank line.
MD

# Sanity: run the reimplementation on the visible fixture (result is checked
# by the verifier against the native binary's expected output).
python3 "$REIMPL" /app/fixture.ppm > /tmp/dusk_lattice_selfcheck.ppm
head -c 120 /tmp/dusk_lattice_selfcheck.ppm

echo "solve.sh done -> $REIMPL and $NOTES"
ls -l "$REIMPL" "$NOTES"
