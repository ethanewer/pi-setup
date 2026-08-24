/* Legacy "pov" renderer - POV-Ray-2.2-era C++ (mid-1990s). */
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
/* NOTE: <string.h> is missing on purpose; strcmp is used below. */

typedef struct { double r, g, b; } Col;
typedef struct { double x, y, rad; Col col; } Sphere;

static char *readline(FILE *f, char *buf, int max)
{
    return fgets(buf, max, f);
}

int main(int argc, char **argv)
{
    const char *scenefile = "scene.pov";
    const char *outfile  = "out.ppm";
    int w = 48, h = 36;
    Col bg = { 0.05, 0.05, 0.10 };
    Sphere sphs[8];
    int n = 0;
    int a;

    for (a = 1; a < argc; a++) {
        if (strcmp(argv[a], "-o") == 0 && a + 1 < argc) outfile = argv[++a];
    }

    FILE *f = fopen(scenefile, "rt");
    if (!f) { fprintf(stderr, "cannot open scene\n"); return 2; }
    char line[256];
    while (readline(f, line, sizeof(line))) {
        char kw[32];
        double ax, ay, az, rad, cr, cg, cb;
        int iw, ih;
        if (sscanf(line, "%31s %lf %lf %lf %lf %lf %lf %lf",
                   kw, &ax, &ay, &az, &rad, &cr, &cg, &cb) == 8 && kw[0] == 's') {
            if (n < 8) {
                sphs[n].x = ax; sphs[n].y = ay; sphs[n].rad = rad;
                sphs[n].col.r = cr; sphs[n].col.g = cg; sphs[n].col.b = cb;
                n++;
            }
        } else if (sscanf(line, "%31s %lf %lf %lf", kw, &cr, &cg, &cb) == 4 && kw[0] == 'b') {
            bg.r = cr; bg.g = cg; bg.b = cb;
        } else if (sscanf(line, "%31s %d %d", kw, &iw, &ih) == 3 && kw[0] == 's' && kw[1] == 'i') {
            w = iw; h = ih;
        }
    }
    fclose(f);

    unsigned char *pix = (unsigned char *)malloc((size_t) w * h * 3);
    int x, y, k;
    for (y = 0; y < h; y++) {
        double v = 1.0 - 2.0 * (double) y / (double) (h - 1);
        for (x = 0; x < w; x++) {
            double u = 2.0 * (double) x / (double) (w - 1) - 1.0;
            Col c = bg;
            for (k = 0; k < n; k++) {
                double du = u - sphs[k].x;
                double dv = v - sphs[k].y;
                if (du * du + dv * dv <= sphs[k].rad * sphs[k].rad)
                    c = sphs[k].col;      /* later spheres paint on top */
            }
            pix[(y * w + x) * 3 + 0] = (unsigned char) (c.r * 255.0 + 0.5);
            pix[(y * w + x) * 3 + 1] = (unsigned char) (c.g * 255.0 + 0.5);
            pix[(y * w + x) * 3 + 2] = (unsigned char) (c.b * 255.0 + 0.5);
        }
    }

    if (write_ppm(outfile, w, h, pix) != 0) return 3;
    free(pix);
    return 0;
}

/* K&R-style function definition (pre-ANSI C++ style). */
int write_ppm(path, w, h, pix)
char *path;
int w, h;
unsigned char *pix;
{
    FILE *out = fopen(path, "wb");
    if (!out) return -1;
    fprintf(out, "P6\n%d %d\n255\n", w, h);
    fwrite(pix, 3, (size_t) (w * h), out);
    fclose(out);
    return 0;
}
