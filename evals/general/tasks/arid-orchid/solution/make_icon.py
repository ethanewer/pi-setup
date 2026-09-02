#!/usr/bin/env python3
"""Renders the Arcadia launch icon (a shaded sphere framed by the sky) and
writes it to out.png. Runs headless -- no display server, no GPU.

The icon carries the project phrase "PEGASUS-VC".
"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

W, H = 640, 420


def main():
    sky = np.zeros((H, W, 3), dtype=np.float32)
    for y in range(H):
        t = y / max(1, H - 1)
        sky[y, :, 0] = 0.42 + 0.42 * t
        sky[y, :, 1] = 0.60 + 0.30 * t
        sky[y, :, 2] = 0.90 + 0.10 * t

    fx = (np.arange(W) + 0.5 - W * 0.5) * (2.0 / W)
    fy = (H * 0.5 - (np.arange(H) + 0.5)) * (2.0 / W)
    X, Y = np.meshgrid(fx, fy)
    R2 = X * X + Y * Y
    inside = R2 < (0.62 * 0.62)
    z = np.sqrt(np.clip(0.62 * 0.62 - R2, 0.0, None))
    nx = np.zeros(R2.shape); ny = np.zeros_like(R2); nz = np.zeros_like(R2)
    nx[inside] = X[inside]; ny[inside] = Y[inside]; nz[inside] = z[inside]
    nl = np.sqrt(nx*nx + ny*ny + nz*nz) + 1e-9
    nx /= nl; ny /= nl; nz /= nl
    li = np.maximum(0.0, nx*0.35 + ny*0.55 + nz*0.80)
    f = 0.22 + 0.78 * li
    img = sky.copy()
    img[inside, 0] = 0.85 * f[inside]
    img[inside, 1] = 0.35 * f[inside]
    img[inside, 2] = 0.22 * f[inside]
    img = np.clip(img, 0.0, 1.0)
    im = Image.fromarray((img * 255).astype(np.uint8), 'RGB')
    dr = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 30)
    except Exception:
        font = ImageFont.load_default()
    dr.text((20, H - 76), "PEGASUS-VC", fill=(250, 248, 240), font=font)
    im.save("/app/out.png")
    return 0


if __name__ == '__main__':
    sys.exit(main())