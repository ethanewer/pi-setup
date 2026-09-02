#!/bin/bash
# Oracle for ivory-kiln: writes the deliverable program /app/solve.py (which
# transcribes the photographed checksum routine and evaluates it), then RUNS it
# on the shipped visible fixtures to produce /app/answer.json. Never reads
# /tests and never cats a precomputed answer.
set -eu

SOLVER="/app/solve.py"
OUT="/app/answer.json"

cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""ivory-kiln solver: recover the integer constants of the photographed
compute(n) routine and evaluate it for n from calib.json.

The photo is rotated/noisy, so raw OCR is unreliable. We binarize/upscale and
try several tesseract page-segmentation modes until all five constants are
recovered with line-anchored patterns; the routine's structure is fixed, only
the literals vary.
"""
import json
import re
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image


def ocr_text(path):
    """Return candidate OCR texts for the photo under several preprocessing
    variants and psm modes."""
    img = Image.open(path).convert("L")
    variants = []
    big = img.resize((img.width * 2, img.height * 2), Image.LANCZOS)
    arr = np.asarray(big)
    variants.append(Image.fromarray(np.where(arr < 128, 0, 255).astype(np.uint8)))
    variants.append(big)
    variants.append(img)
    texts = []
    for v in variants:
        with tempfile.NamedTemporaryFile(suffix=".png") as tf:
            v.save(tf.name)
            for psm in ("6", "3"):
                r = subprocess.run(
                    ["tesseract", tf.name, "-", "--psm", psm],
                    capture_output=True, text=True,
                )
                if r.returncode == 0 and r.stdout:
                    texts.append(r.stdout)
    return texts


def parse(text):
    """Extract (L, U, F, S, K) from one OCR text, or None.

    Patterns are anchored on the routine's fixed line structure (assignments
    of the form 'total = total ...' and the return line) rather than on exact
    keywords, because OCR routinely mangles individual tokens (e.g. 'range'
    -> 'Fange', 'n * 11' -> 'ne*(R) 11')."""
    L = U = F = S = K = None
    for line in text.splitlines():
        m = re.search(r"\(\s*(\d+)\s*,\s*(\d+)\s*\)", line)
        if m and L is None and re.search(r"(for|ange|unge|rango)", line):
            L, U = int(m.group(1)), int(m.group(2))
        m = re.search(r"total\s*=\s*total\s*\*\s*(\d+)", line)
        if m and F is None:
            F = int(m.group(1))
        # scaling line: 'total = total + <token starting with n> * <int>'
        m = re.search(r"total\s*=\s*total\s*\+\s*(\S*n\S*)\s*\**(.*)$", line)
        if m and S is None and m.group(1) != "i":
            nums = re.findall(r"\d+", m.group(2))
            if nums:
                S = int(nums[-1])
        m = re.search(r"return\s+total\s*-\s*(\d+)", line)
        if m and K is None:
            K = int(m.group(1))
    if L is None:
        m = re.search(r"\(\s*(\d+)\s*,\s*(\d+)\s*\)", text)
        if m:
            L, U = int(m.group(1)), int(m.group(2))
    if None in (L, U, F, S, K):
        return None
    return L, U, F, S, K


def main():
    photo, calib, out = sys.argv[1], sys.argv[2], sys.argv[3]
    n = int(json.load(open(calib))["n"])
    result = None
    for text in ocr_text(photo):
        parsed = parse(text)
        if parsed:
            result = parsed
            break
    if result is None:
        raise SystemExit("could not transcribe constants from %s" % photo)
    L, U, F, S, K = result
    total = sum(i * i for i in range(L, U)) * F + n * S - K
    with open(out, "w") as fh:
        json.dump({"code_value": int(total)}, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# Run the produced program on the visible fixtures to generate the output.
python3 "$SOLVER" /app/code.png /app/calib.json "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
