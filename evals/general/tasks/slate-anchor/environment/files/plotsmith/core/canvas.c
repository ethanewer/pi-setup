#include "canvas.h"

/* The canvas is 1 bit per pixel: 0 = paper (white), 1 = ink (black).
 * Every primitive clips: pixels outside [0,PLW) x [0,PLH) are ignored. */

void pl_clear(unsigned char *pix) {
    for (int i = 0; i < PLW * PLH; ++i) pix[i] = 0;
}

void pl_dot(unsigned char *pix, int x, int y) {
    if (x < 0 || x >= PLW || y < 0 || y >= PLH) return;
    pix[y * PLW + x] = 1;
}

void pl_hline(unsigned char *pix, int x1, int x2, int y) {
    if (x1 > x2) { int t = x1; x1 = x2; x2 = t; }
    int lo = x1 > 0 ? x1 : 0;
    int hi = x2 < PLW - 1 ? x2 : PLW - 1;
    for (int x = lo; x <= hi; ++x) pl_dot(pix, x, y);
}

void pl_vline(unsigned char *pix, int x, int y1, int y2) {
    if (y1 > y2) { int t = y1; y1 = y2; y2 = t; }
    int lo = y1 > 0 ? y1 : 0;
    int hi = y2 < PLH - 1 ? y2 : PLH - 1;
    for (int y = lo; y <= hi; ++y) pl_dot(pix, x, y);
}

void pl_rect(unsigned char *pix, int x, int y, int w, int h) {
    if (w <= 0 || h <= 0) return;
    int x2 = x + w - 1, y2 = y + h - 1;
    int lo = x > 0 ? x : 0;
    int hi = x2 < PLW - 1 ? x2 : PLW - 1;
    for (int xx = lo; xx <= hi; ++xx) { pl_dot(pix, xx, y); pl_dot(pix, xx, y2); }
    lo = y > 0 ? y : 0;
    hi = y2 < PLH - 1 ? y2 : PLH - 1;
    for (int yy = lo; yy <= hi; ++yy) { pl_dot(pix, x, yy); pl_dot(pix, x2, yy); }
}

void pl_fill(unsigned char *pix, int x, int y, int w, int h) {
    if (w <= 0 || h <= 0) return;
    int x2 = x + w - 1, y2 = y + h - 1;
    int xlo = x > 0 ? x : 0, xhi = x2 < PLW - 1 ? x2 : PLW - 1;
    int ylo = y > 0 ? y : 0, yhi = y2 < PLH - 1 ? y2 : PLH - 1;
    for (int yy = ylo; yy <= yhi; ++yy)
        for (int xx = xlo; xx <= xhi; ++xx)
            pix[yy * PLW + xx] = 1;
}
