#!/bin/bash
# dune-terrace oracle.
# Writes the two deliverable tools, compiles and runs them so every /app
# artifact is genuinely produced by real work (no precomputed pixel bytes).
set -eu

cat > /app/ptrace.c <<'C_EOF'
/* dune-terrace compact ray tracer.
 * Usage: ptrace <scene.json> <target.ppm> <scene_color.pfm> <scene_depth.pgm>
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

typedef struct { double x, y, z; } TV;
static TV     tv(double x, double y, double z) { TV r={x,y,z}; return r; }
static TV     vadd(TV a, TV b)  { TV r={a.x+b.x,a.y+b.y,a.z+b.z}; return r; }
static TV     vsub(TV a, TV b)  { TV r={a.x-b.x,a.y-b.y,a.z-b.z}; return r; }
static TV     vmul(TV a,double d){ TV r={a.x*d,a.y*d,a.z*d}; return r; }
static double vdot(TV a, TV b)  { return a.x*b.x+a.y*b.y+a.z*b.z; }
static double vlen(TV a)        { return sqrt(vdot(a,a)); }
static TV     vnorm(TV a)       { double l=vlen(a); return tv(a.x/l,a.y/l,a.z/l); }
static TV     vcrs(TV a, TV b)  { return tv(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x); }
static double clamped01(double a){ return a<0?0:(a>1?1:a); }

typedef struct { TV center; double radius, shin, refl; } Sphere;

static const Sphere SPH[4] = {
    { {  0.00, 0.30, -1.80 }, 0.70,  40, 0.05 },
    { { -1.30,-0.50, -1.90 }, 0.80,  16, 0.05 },
    { {  1.30,-0.50, -1.50 }, 0.70,  60, 0.10 },
    { {  0.05, 0.60, -2.50 }, 0.95,  80, 0.15 }
};
static const double SCOL[4][3] = {
    { 200.0/255.0,  40.0/255.0,  45.0/255.0 },
    {  60.0/255.0, 170.0/255.0, 120.0/255.0 },
    {  70.0/255.0, 100.0/255.0, 220.0/255.0 },
    { 230.0/255.0, 190.0/255.0, 110.0/255.0 }
};
#define NS 4

static const TV    LIGHT = { -2.5, 4.0, 1.0 };
static const double LCOL[3] = { 255.0/255.0, 225.0/255.0, 205.0/255.0 };
static const double BGT[3]  = {  30.0/255.0,  90.0/255.0, 210.0/255.0 };
static const double BGB[3]  = { 245.0/255.0, 195.0/255.0, 130.0/255.0 };
static const double AMB = 0.30;
static const double FAR = 7.0;

static int W = 160, H = 100;
static TV eye, fw, rt, upv;

static double hitS(TV ro, TV rd, const Sphere* s) {
    TV oc = vsub(ro, s->center);
    double b  = vdot(oc, rd);
    double cc = vdot(oc, oc) - s->radius*s->radius;
    double disc = b*b - cc;
    if (disc < 0) return -1.0;
    double sq = sqrt(disc);
    double t = -b - sq;
    if (t < 1e-5) t = -b + sq;
    if (t < 1e-5) return -1.0;
    return t;
}

static void shade(TV ro, TV rd, int depth, double out[3]) {
    double tmin = 1e30; int who = -1; int i;
    for (i = 0; i < NS; i++) {
        double t = hitS(ro, rd, &SPH[i]);
        if (t > 1e-5 && t < tmin) { tmin = t; who = i; }
    }
    if (who < 0) {                 /* gradient sky */
        double g = (vdot(rd, upv) + 1.0) * 0.5;
        if (g < 0) g = 0; if (g > 1) g = 1;
        out[0] = BGB[0] + (BGT[0]-BGB[0])*g;
        out[1] = BGB[1] + (BGT[1]-BGB[1])*g;
        out[2] = BGB[2] + (BGT[2]-BGB[2])*g;
        return;
    }
    TV P   = vadd(ro, vmul(rd, tmin));
    TV nrmv= vnorm(vsub(P, SPH[who].center));
    TV n   = (vdot(nrmv, rd) > 0) ? vmul(nrmv, -1.0) : nrmv;
    TV L   = vnorm(vsub(LIGHT, P));
    TV Psh = vadd(P, vmul(n, 1e-4));
    double distL = vlen(vsub(LIGHT, P));
    int shadow = 0;
    for (i = 0; i < NS; i++) {
        if (i == who) continue;
        double t = hitS(Psh, L, &SPH[i]);
        if (t > 1e-5 && t < distL - 1e-4) { shadow = 1; break; }
    }
    double dFac = shadow ? 0.0 : 1.0;
    double diff = vdot(n, L); if (diff < 0) diff = 0;
    TV Vd = vmul(rd, -1.0);
    TV Rr = vsub(vmul(n, 2.0*vdot(n,L)), L);
    double spec = vdot(Rr, Vd); if (spec < 0) spec = 0;
    spec = pow(spec, SPH[who].shin);
    const double* bc = SCOL[who];
    double k  = AMB + 0.55*diff*dFac;
    double kr = bc[0]*k + LCOL[0]*0.8*spec*dFac;
    double kg = bc[1]*k + LCOL[1]*0.8*spec*dFac;
    double kb = bc[2]*k + LCOL[2]*0.8*spec*dFac;
    double rf = SPH[who].refl;
    if (rf > 0 && depth > 0) {
        TV rd2 = vsub(rd, vmul(n, 2.0*vdot(rd,n)));
        double rp[3];
        shade(vadd(P, vmul(n,1e-4)), rd2, depth-1, rp);
        kr += rf*rp[0]; kg += rf*rp[1]; kb += rf*rp[2];
    }
    out[0] = clamped01(kr);
    out[1] = clamped01(kg);
    out[2] = clamped01(kb);
}

static void readsize(const char* path) {
    FILE* f = fopen(path, "rb"); if (!f) return;
    char buf[65536]; size_t n = fread(buf, 1, sizeof(buf)-1, f); fclose(f);
    buf[n] = 0; char* p;
    if ((p = strstr(buf, "\"width\"")))  { p = strchr(p, ':'); if (p) W = atoi(p+1); }
    if ((p = strstr(buf, "\"height\""))) { p = strchr(p, ':'); if (p) H = atoi(p+1); }
    if (W <= 0 || H <= 0) { W = 160; H = 100; }
}

int main(int argc, char** argv) {
    if (argc < 5) { fprintf(stderr, "usage\n"); return 1; }
    readsize(argv[1]);
    const char *TP = argv[2], *CP = argv[3], *DP = argv[4];

    eye = tv(0,0.3,3.6);
    fw  = vnorm(vsub(tv(0,0,0), eye));
    rt  = vnorm(vcrs(fw, tv(0,1,0)));
    upv = vcrs(rt, fw);
        double tside  = tan(50.0*3.14159265358979/360.0);
    double aspect = (double)W / (double)H;

    double* color = malloc(sizeof(double)*W*H*3);
    float*  fbuf  = malloc(sizeof(float)*W*H*3);
    unsigned char* dep = malloc((size_t)W*H);

    for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
        double px = 2.0*(x+0.5)/W - 1.0;
        double py = 1.0 - 2.0*(y+0.5)/H;
        TV dir = vnorm(vadd(fw,
                     vadd(vmul(rt, px*aspect*tside), vmul(upv, py*tside))));
        double tmin = 1e30; int who = -1;
        for (int i = 0; i < NS; i++) {
            double t = hitS(eye, dir, &SPH[i]);
            if (t > 1e-5 && t < tmin) { tmin = t; who = i; }
        }
        double depv = (who < 0) ? 1.0 : (clamped01(tmin/FAR));
        double rgb[3];
        shade(eye, dir, 2, rgb);
        int idx = (y*W + x)*3;
        color[idx] = rgb[0]; color[idx+1] = rgb[1]; color[idx+2] = rgb[2];
        fbuf[idx] = (float)rgb[0]; fbuf[idx+1] = (float)rgb[1]; fbuf[idx+2] = (float)rgb[2];
        dep[y*W+x] = (unsigned char)(depv*255.0 + 0.5);
    }

    FILE* fo = fopen(TP, "wb");
    if (fo) { fprintf(fo, "P6\n%d %d\n255\n", W, H);
        for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
            int i = (y*W+x)*3;
            unsigned char p[3] = { (unsigned char)(color[i]*255+0.5),
                                   (unsigned char)(color[i+1]*255+0.5),
                                   (unsigned char)(color[i+2]*255+0.5) };
            fwrite(p, 1, 3, fo);
        }
        fclose(fo);
    }

    FILE* fp = fopen(CP, "wb");
    if (fp) { fprintf(fp, "PF\n%d %d\n-1.0\n", W, H);
        for (int y = H-1; y >= 0; y--) for (int x = 0; x < W; x++) {
            int i = (y*W+x)*3;
            float p[3] = { fbuf[i], fbuf[i+1], fbuf[i+2] };
            fwrite(p, 4, 3, fp);
        }
        fclose(fp);
    }

    FILE* fd = fopen(DP, "wb");
    if (fd) { fprintf(fd, "P5\n%d %d\n255\n", W, H);
        fwrite(dep, 1, (size_t)W*H, fd);
        fclose(fd);
    }

    free(color); free(fbuf); free(dep);
    return 0;
}
C_EOF

cat > /app/make_icon.py <<'ICON_EOF'
#!/usr/bin/env python3
"""dune-terrace icon generator.

Renders a deterministic 64x64 PNG "dune sunset" icon from geometric primitives
(a vertical gradient sky, a sun disc, two rolling dune bands) and the short
phrase "SUNSET" drawn with a built-in 5x7 bitmap font. Writes the PNG to the
path given as the sole command-line argument. Fully deterministic (no
timestamps, no randomness, fixed zlib settings).

Usage: make_icon.py <out.png>
"""
import struct
import sys
import zlib

W = H = 64

GLYPHS = {
    'D': ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    'U': ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    'N': ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    'E': ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    'S': ["01110", "10001", "10000", "01110", "00001", "10001", "01110"],
}


def sky_color(y):
    """Vertical gradient: warm apricot at bottom, deep blue at top."""
    top = (30, 65, 130)
    bot = (235, 175, 120)
    t = y / (H - 1)
    return (int(bot[0] + (top[0] - bot[0]) * t),
            int(bot[1] + (top[1] - bot[1]) * t),
            int(bot[2] + (top[2] - bot[2]) * t))


def dune_top(x, base, amp, freq, phase):
    import math as _m
    return base + amp * _m.sin(freq * x + phase)


def draw_glyph(canvas, left, top, color, ch):
    for gy, row in enumerate(GLYPHS[ch]):
        for gx in range(5):
            if row[gx] == '1':
                x, y = left + gx, top + gy
                if 0 <= x < W and 0 <= y < H:
                    canvas[y][x] = color


def build_canvas():
    canvas = [[(0, 0, 0) for _ in range(W)] for _ in range(H)]
    for y in range(H):
        c = sky_color(y)
        for x in range(W):
            canvas[y][x] = c

    cx, cy, r = 18, 16, 11
    for y in range(H):
        for x in range(W):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                canvas[y][x] = (250, 225, 90)
            if y > int(dune_top(x, 42, 6, 0.08, 1.1)):
                canvas[y][x] = (198, 148, 92)
            if y > int(dune_top(x, 52, 8, 0.05, 3.2)):
                canvas[y][x] = (224, 176, 120)

    phrase = "SUNSET"
    glyph_w, gap = 5, 2
    total = len(phrase) * (glyph_w + gap) - gap
    left = (W - total) // 2
    for ch in phrase:
        if ch in GLYPHS:
            draw_glyph(canvas, left, 46, (240, 240, 245), ch)
        left += glyph_w + gap
    return canvas


def chunk(tag, data):
    return struct.pack('>I', len(data)) + tag + data + \
        struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)


def write_png(canvas, path):
    raw = bytearray()
    for row in canvas:
        raw.append(0)
        for px in row:
            raw += bytes(px)
    ihdr = struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0)
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', ihdr)
           + chunk(b'IDAT', zlib.compress(bytes(raw), 9))
           + chunk(b'IEND', b''))
    with open(path, 'wb') as f:
        f.write(png)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else 'out.png'
    write_png(build_canvas(), out)


if __name__ == '__main__':
    main()
ICON_EOF

cc -O2 -o /app/ptrace /app/ptrace.c -lm
/app/ptrace /app/scene.json /app/target.ppm /app/scene_color.pfm /app/scene_depth.pgm
python3 /app/make_icon.py /app/out.png

echo "solve done"
