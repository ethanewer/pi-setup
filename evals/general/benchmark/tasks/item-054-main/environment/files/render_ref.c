/* Reference tracer — authoritative implementation (do not ship to /app).
 *
 * Reads a POV-like scene:  size W H | background r g b | sphere x y r R G B
 * and writes a binary P6 PPM. Projection: NDC u=2px/(W-1)-1, v=1-2py/(H-1);
 * world coords are divided by focal F=1.5; flat fill, later spheres on top.
 */
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
                if (du * du + dv * dv <= R * R) {
                    r = sph[i].cr / 255.0; g = sph[i].cg / 255.0; b = sph[i].cb / 255.0;
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