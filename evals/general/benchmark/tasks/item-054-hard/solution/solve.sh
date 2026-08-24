#!/bin/bash
set -euo pipefail

# Oracle solution: implement the shaded, focal-1.5 renderer that matches
# render_ref on every scene, compile it, and verify against the sample.
cat > /app/pov/tracer.c <<'CEOF'
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { double x, y, r; unsigned char cr, cg, cb; } Sphere;

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: %s scene.pov out.ppm\n", argv[0]); return 1; }
    FILE *f = fopen(argv[1], "r");
    if (!f) { perror("scene"); return 1; }
    int W = 64, H = 48;
    double bg[3] = {0.05, 0.05, 0.10};
    Sphere sph[256];
    int n = 0;
    char line[512];
    while (fgets(line, sizeof line, f)) {
        double a, b, c, d, e, g;
        if (sscanf(line, "size %d %d", &W, &H) == 2) continue;
        if (sscanf(line, "background %lf %lf %lf", &bg[0], &bg[1], &bg[2]) == 3) continue;
        if (sscanf(line, "sphere %lf %lf %lf %lf %lf %lf", &a, &b, &c, &d, &e, &g) == 6) {
            sph[n].x = a; sph[n].y = b; sph[n].r = c;
            sph[n].cr = (unsigned char)(d * 255.0 + 0.5);
            sph[n].cg = (unsigned char)(e * 255.0 + 0.5);
            sph[n].cb = (unsigned char)(g * 255.0 + 0.5);
            n++;
        }
    }
    fclose(f);
    const double F = 1.5;
    unsigned char *pix = malloc((size_t)W * H * 3);
    for (int py = 0; py < H; py++) {
        double v = 1.0 - 2.0 * (double)py / (H - 1);
        for (int px = 0; px < W; px++) {
            double u = 2.0 * (double)px / (W - 1) - 1.0;
            double r = bg[0], g = bg[1], b = bg[2];
            for (int i = 0; i < n; i++) {
                double du = u - sph[i].x / F;
                double dv = v - sph[i].y / F;
                double R = sph[i].r / F;
                double d2 = du * du + dv * dv;
                if (R > 0.0 && d2 <= R * R) {
                    double t = sqrt(d2) / R;
                    double shade = 0.72 + 0.28 * (1.0 - t);
                    r = (sph[i].cr / 255.0) * shade;
                    g = (sph[i].cg / 255.0) * shade;
                    b = (sph[i].cb / 255.0) * shade;
                }
            }
            size_t idx = ((size_t)py * W + px) * 3;
            pix[idx] = (unsigned char)(r * 255.0 + 0.5);
            pix[idx + 1] = (unsigned char)(g * 255.0 + 0.5);
            pix[idx + 2] = (unsigned char)(b * 255.0 + 0.5);
        }
    }
    char buf[128];
    snprintf(buf, sizeof buf, "P6\n%d %d\n255\n", W, H);
    FILE *o = fopen(argv[2], "wb");
    if (!o) { perror("out"); free(pix); return 1; }
    fwrite(buf, 1, strlen(buf), o);
    fwrite(pix, 1, (size_t)W * H * 3, o);
    fclose(o);
    free(pix);
    return 0;
}
CEOF

cd /app/pov
gcc -O2 -o tracer tracer.c -lm
./tracer scene0.pov /tmp/tracer_sample.ppm
./render_ref scene0.pov /tmp/ref_sample.ppm
cmp /tmp/tracer_sample.ppm /tmp/ref_sample.ppm