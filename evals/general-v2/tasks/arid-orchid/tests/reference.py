#!/usr/bin/env python3
"""Arcadia offscreen scene renderer -- independent OSMOSIS-free reference.

This is the verifier's ground-truth rasterizer. It reads a plain-text scene
description and writes a color PFM and a grayscale depth PGM, using the exact
geometric + shading model documented in instruction.md:

  * eye at origin looking down +Z, unit focal plane (square pixels);
  * scene = set of diffuse spheres on a constant (background) colour;
  * one directional light; surface colour = base*(amb + (1-amb)*max(0,n.L));
  * depth  = round(255 * clamp(1/(1+t),0,1)); background depth = 0.

The implementation is deliberately single-pass and deterministic so that any
correct re-implementation (C, numpy, ...) lands within tolerance of it.
"""
import sys, math
import numpy as np


def math_len(v):
    return math.sqrt(v[0]**2 + v[1]**2 + v[2]**2)


def parse(path):
    W = H = 32; bg = (0.0, 0.0, 0.0); amb = 0.35; L = None; spheres = []
    with open(path) as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith('#'):
                continue
            tok = line.split()
            k = tok[0].lower()
            if k == 'bg':
                bg = tuple(float(x) for x in tok[1:4])
            elif k in ('amb', 'ambi'):
                amb = float(tok[1])
            elif k == 'l':
                L = tuple(float(x) for x in tok[1:4])
            elif k == 's':
                spheres.append(tuple(float(x) for x in tok[1:8]))
            else:
                # two bare ints => resolution
                try:
                    W = int(float(tok[0])); H = int(float(tok[1]))
                except Exception:
                    pass
    if L is None:
        L = (0.6, 0.8, 0.4)
    W = max(1, min(1024, int(W))); H = max(1, min(1024, int(H)))
    return W, H, bg, amb, L, spheres


def render(sc, px, py):
    """Return (colour_rgb tuple, depth01) for a directional sample (px,py,z=1)."""
    W, H, bg, amb, L, spheres = sc
    d = (px, py, 1.0)
    dl = math_len(d)
    d = (d[0]/dl, d[1]/dl, d[2]/dl)
    best_t = None; best_ref = None
    for (cx, cy, cz, r, cr, cg, cb) in spheres:
        oc = (-cx, -cy, -cz)
        b = oc[0]*d[0] + oc[1]*d[1] + oc[2]*d[2]
        c = oc[0]*oc[0] + oc[1]*oc[1] + oc[2]*oc[2] - r*r
        disc = b*b - c
        if disc <= 0.0:
            continue
        sq = math.sqrt(disc)
        tmin = -b - sq
        if tmin < 1e-4:
            tmin = -b + sq
        if tmin < 1e-4:
            continue
        hx = tmin*d[0]-cx; hy = tmin*d[1]-cy; hz = tmin*d[2]-cz
        nlen = math.sqrt(hx*hx+hy*hy+hz*hz)
        if best_t is None or tmin < best_t:
            best_t = tmin
            best_ref = ((cr, cg, cb), (hx/nlen, hy/nlen, hz/nlen))
    if best_t is None:
        return bg, 0
    (cr, cg, cb), (nx, ny, nz) = best_ref
    ll = math_len(L)
    Ln = (L[0]/ll, L[1]/ll, L[2]/ll)
    li = max(0.0, nx*Ln[0] + ny*Ln[1] + nz*Ln[2])
    f = amb + (1.0-amb)*li
    col = (cr*f, cg*f, cb*f)
    depth = round(255.0*min(1.0, max(0.0, 1.0/(1.0+best_t))))
    return col, depth


def main():
    if len(sys.argv) < 4:
        sys.exit("usage: reference.py scene.cfg out.pfm out.pgm")
    sc = parse(sys.argv[1])
    W, H = sc[0], sc[1]
    color = np.zeros((H, W, 3), dtype=np.float32)
    depth = np.zeros((H, W), dtype=np.uint8)
    for y in range(H):
        fy = (H*0.5 - (y+0.5)) * (2.0/W)
        for x in range(W):
            fx = ((x+0.5) - W*0.5) * (2.0/W)
            c, d = render(sc, fx, fy)
            color[y, x, 0], color[y, x, 1], color[y, x, 2] = c
            depth[y, x] = d
    color = np.clip(color, 0.0, 1.0)
    with open(sys.argv[2], 'wb') as f:
        f.write(b"PF\n%d %d\n-1.0\n" % (W, H))
        color.astype('<f4').tofile(f)
    with open(sys.argv[3], 'w') as f:
        f.write("P2\n%d %d\n255\n" % (W, H))
        flat = depth.ravel()
        for i in range(0, len(flat), 32):
            f.write(" ".join(str(int(v)) for v in flat[i:i+32]) + "\n")
    return 0


if __name__ == '__main__':
    sys.exit(main())