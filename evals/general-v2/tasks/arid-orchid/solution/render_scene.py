#!/usr/bin/env python3
"""Arcadia offscreen scene rasterizer (color + depth).

Reads a plain-text scene description (same format as instruction.md) and
writes two raster files through a pure offscreen / headless buffer path:

    render_scene.py <scene.cfg> <out_color.pfm> <out_depth.pgm>

* color  : color PFM  (FP floats, "PF" line, scale -1.0)
* depth  : grayscale PGM  (P2 ascii) with depth = round(255*clamp(1/(1+t),0,1))

Shading = diffuse lambert on a constant ambient + one directional light,
exactly as documented.  No display server is required.
"""
import sys, math


def parse(path):
    W = H = 32; bg = (0.0, 0.0, 0.0); amb = 0.35; L = None; sph = []
    with open(path) as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith('#'):
                continue
            t = line.split()
            k = t[0].lower()
            if k == 'bg':
                bg = tuple(float(x) for x in t[1:4])
            elif k in ('ambi', 'amb'):
                amb = float(t[1])
            elif k == 'l':
                L = tuple(float(x) for x in t[1:4])
            elif k == 's':
                sph.append(tuple(float(x) for x in t[1:8]))
            else:
                try:
                    W = int(float(t[0])); H = int(float(t[1]))
                except Exception:
                    pass
    if L is None:
        L = (0.6, 0.8, 0.4)
    W = max(1, min(1024, W)); H = max(1, min(1024, H))
    return W, H, bg, amb, L, sph


def pixel(sc, px, py):
    W, H, bg, amb, L, sph = sc
    d = (px, py, 1.0)
    dl = math.sqrt(d[0]*d[0]+d[1]*d[1]+d[2]*d[2])
    d = (d[0]/dl, d[1]/dl, d[2]/dl)
    best = None
    for (cx, cy, cz, r, cr, cg, cb) in sph:
        ocx, ocy, ocz = -cx, -cy, -cz
        b = ocx*d[0]+ocy*d[1]+ocz*d[2]
        c = ocx*ocx+ocy*ocy+ocz*ocz-r*r
        disc = b*b-c
        if disc <= 0:
            continue
        sq = math.sqrt(disc)
        tmin = -b-sq
        if tmin < 1e-4:
            tmin = -b+sq
        if tmin < 1e-4:
            continue
        if best is None or tmin < best[0]:
            hx = tmin*d[0]-cx; hy = tmin*d[1]-cy; hz = tmin*d[2]-cz
            nl = math.sqrt(hx*hx+hy*hy+hz*hz)
            best = (tmin, (cr, cg, cb), (hx/nl, hy/nl, hz/nl))
    if best is None:
        return bg, 0
    t, (cr, cg, cb), (nx, ny, nz) = best
    ll = math.sqrt(L[0]**2+L[1]**2+L[2]**2)
    li = max(0.0, nx*L[0]/ll+ny*L[1]/ll+nz*L[2]/ll)
    f = amb + (1.0-amb)*li
    return (cr*f, cg*f, cb*f), min(255, max(0, round(255.0*(1.0/(1.0+t)))))


def main():
    if len(sys.argv) < 4:
        sys.exit("usage: render_scene.py scene.cfg out_color.pfm out_depth.pgm")
    sc = parse(sys.argv[1])
    W, H = sc[0], sc[1]
    color = [0.0]*(W*H*3); depth = [0]*(W*H)
    for y in range(H):
        fy = (H*0.5-(y+0.5))*(2.0/W)
        for x in range(W):
            fx = ((x+0.5)-W*0.5)*(2.0/W)
            c, dd = pixel(sc, fx, fy)
            i = (y*W+x)
            color[i*3] = max(0.0, min(1.0, c[0]))
            color[i*3+1] = max(0.0, min(1.0, c[1]))
            color[i*3+2] = max(0.0, min(1.0, c[2]))
            depth[i] = dd
    with open(sys.argv[2], 'wb') as f:
        f.write(b"PF\n%d %d\n-1.0\n" % (W, H))
        import struct
        for v in color:
            f.write(struct.pack('<f', float(v)))
    with open(sys.argv[3], 'w') as f:
        f.write("P2\n%d %d\n255\n" % (W, H))
        for i in range(0, len(depth), 32):
            f.write(" ".join(str(int(v)) for v in depth[i:i+32]) + "\n")
    return 0


if __name__ == '__main__':
    sys.exit(main())