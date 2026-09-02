#pragma once
#define PLW 24
#define PLH 16

void pl_clear(unsigned char *pix);
void pl_dot(unsigned char *pix, int x, int y);
void pl_hline(unsigned char *pix, int x1, int x2, int y);
void pl_vline(unsigned char *pix, int x, int y1, int y2);
void pl_rect(unsigned char *pix, int x, int y, int w, int h);
void pl_fill(unsigned char *pix, int x, int y, int w, int h);
