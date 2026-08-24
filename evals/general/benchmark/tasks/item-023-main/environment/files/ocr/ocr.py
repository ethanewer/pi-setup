"""Deterministic OCR engine for item-023.

Transcribes the black-on-white monospace text shown in a video frame back to
the exact string, by matching each fixed-width glyph cell against pre-rendered
per-character templates stored alongside this module.

API:
    ocr.get_text(path)   -> str (the transcribed line)

The frames and the glyph templates were rendered with the same monospaced TTF
at the same point size, so the match is exact and deterministic.
"""
import glob
import os

from PIL import Image

_HERE = os.path.dirname(os.path.abspath(__file__))
_GLYPHS = os.path.join(_HERE, 'glyphs')

# Rendering constants (shared with the asset renderer).
_CELL_W = 154
_CELL_H = 386
_PAD_X = 154   # text is left-justified, starting at x == one cell width
_PAD_Y = 154   # text top edge

_WHITE = 255


def _templates():
    tpl = {}
    for p in glob.glob(os.path.join(_GLYPHS, '*.png')):
        code = int(os.path.basename(p).split('.')[0])
        im = Image.open(p).convert('L')
        assert im.size == (_CELL_W, _CELL_H)
        tpl[code] = im
    return tpl


_TEMPLATES = _templates()


def _diff(a, b):
    """Count pixels that differ between two equal-size L images."""
    pa = a.tobytes()
    pb = b.tobytes()
    return sum(1 for x, y in zip(pa, pb) if x != y)


def _blank(img):
    return all(v == _WHITE for v in img.tobytes())


def ocr_image(im):
    w, h = im.size
    text = []
    cell_bytes = None
    ncol = w // _CELL_W
    for k in range(ncol):
        x0 = k * _CELL_W
        x1 = x0 + _CELL_W
        y0 = _PAD_Y
        y1 = y0 + _CELL_H
        if x1 > w or y1 > h:
            break
        region = im.crop((x0, y0, x1, y1))
        if _blank(region):
            text.append(' ')
            continue
        best = chr(32)
        bestd = None
        for code, t in _TEMPLATES.items():
            if code == 32:
                continue
            d = _diff(region, t)
            if bestd is None or d < bestd:
                bestd = d
                best = chr(code)
        text.append(best)
    line = ''.join(text)
    return line.strip()


def ocr(path):
    return ocr_image(Image.open(path).convert('L'))


INF = float('inf')