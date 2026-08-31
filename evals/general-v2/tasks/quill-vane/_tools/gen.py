#!/usr/bin/env python3
"""Generate fixtures for quill-vane: renders the code photos + computes ground truth."""
import json
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ENV = ROOT / "environment" / "files" / "snippets"
TESTS = ROOT / "tests"
FONT = "/System/Library/Fonts/Menlo.ttc"

FUNC_A = '''def func_a(n):
    acc = 7
    for k in range(3, 12, 2):
        acc = acc * 4 - k
    if acc % 3 == 0:
        acc = acc // 3
    return acc + 2 * n
'''

FUNC_B = '''def func_b(s):
    out = ""
    idx = 0
    while idx < len(s):
        ch = s[idx]
        if "a" <= ch <= "z":
            out = chr((ord(ch) - 97 + 11) % 26 + 97) + out
        else:
            out = out + ch
        idx = idx + 2
    return out
'''

FUNC_C = '''def func_c(xs):
    total = 0
    for i in range(len(xs)):
        v = xs[i]
        if v % 2 == 0:
            total = total + v * i
        else:
            total = total - v
    if total < 0:
        total = 0 - total
    return total % 1000
'''


def true_a(n):
    acc = 7
    for k in range(3, 12, 2):
        acc = acc * 4 - k
    if acc % 3 == 0:
        acc = acc // 3
    return acc + 2 * n


def true_b(s):
    out = ""
    idx = 0
    while idx < len(s):
        ch = s[idx]
        if "a" <= ch <= "z":
            out = chr((ord(ch) - 97 + 11) % 26 + 97) + out
        else:
            out = out + ch
        idx = idx + 2
    return out


def true_c(xs):
    total = 0
    for i in range(len(xs)):
        v = xs[i]
        if v % 2 == 0:
            total = total + v * i
        else:
            total = total - v
    if total < 0:
        total = 0 - total
    return total % 1000


def render(code_text: str, out_path: Path, seed: int) -> None:
    """Render code small, gray, speckled and slightly blurred: hostile to
    off-the-shelf OCR, still legible to a careful reader."""
    rng = random.Random(seed)
    scale = 3
    font = ImageFont.truetype(FONT, 13 * scale)
    lines = code_text.rstrip("\n").split("\n")
    char_w = font.getbbox("M")[2]
    line_h = int(15 * scale)
    pad = 14 * scale
    width = pad * 2 + char_w * max(len(l) for l in lines)
    height = pad * 2 + line_h * len(lines)
    img = Image.new("L", (width, height), 252)
    draw = ImageDraw.Draw(img)
    y = pad
    for line in lines:
        x = pad + rng.randint(-2, 2) * scale // 2
        draw.text((x, y), line, fill=78, font=font)
        y += line_h
    img = img.resize((width // scale, height // scale), Image.LANCZOS)
    img = img.filter(ImageFilter.GaussianBlur(0.4))
    px = img.load()
    w, h = img.size
    for _ in range(int(w * h * 0.035)):
        xx, yy = rng.randrange(w), rng.randrange(h)
        px[xx, yy] = max(0, min(255, px[xx, yy] + rng.choice((-30, 30))))
    img.save(out_path)


PROBE = {"func_a": 310, "func_b": "GraniteFjord7", "func_c": [5, 8, 13, 2, 40, 7, 22]}
HIDDEN = {
    "H1": {"func_a": 1234, "func_b": "shadowQuartz9", "func_c": [3, 10, 4, 7, 6, 21, 8, 9]},
    "H2": {"func_a": 999983, "func_b": "MississippiRiver", "func_c": [2]},
    "H3": {"func_a": 41, "func_b": "zz Top!", "func_c": [1, 1, 2, 3, 5, 8, 13, 21, 34, 55]},
}


def evaluate(args):
    return {
        "func_a": true_a(args["func_a"]),
        "func_b": true_b(args["func_b"]),
        "func_c": true_c(args["func_c"]),
    }


def main():
    ENV.mkdir(parents=True, exist_ok=True)
    render(FUNC_A, ENV / "func_a.png", seed=101)
    render(FUNC_B, ENV / "func_b.png", seed=202)
    render(FUNC_C, ENV / "func_c.png", seed=303)
    (ROOT / "environment" / "files" / "probe.json").write_text(
        json.dumps(PROBE, indent=2) + "\n")
    TESTS.mkdir(parents=True, exist_ok=True)
    (TESTS / "expected.json").write_text(json.dumps(evaluate(PROBE), indent=2) + "\n")
    for case, args in HIDDEN.items():
        d = TESTS / "hidden" / case
        d.mkdir(parents=True, exist_ok=True)
        (d / "probe.json").write_text(json.dumps(args, indent=2) + "\n")
        (d / "expected.json").write_text(json.dumps(evaluate(args), indent=2) + "\n")
    print("visible expected:", evaluate(PROBE))
    for case, args in HIDDEN.items():
        print(case, evaluate(args))


if __name__ == "__main__":
    main()
