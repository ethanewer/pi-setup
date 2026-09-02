#pragma once
#include <stdio.h>

/* Write the canvas as plain ASCII PBM ("P1"): the header "P1", the line
 * "<W> <H>", then H rows of W tokens "0"/"1" (0 = paper, 1 = ink) separated
 * by single spaces, one row per line, newline-terminated. Returns 0 on
 * success. */
int pl_write_pbm(const char *path, const unsigned char *pix, int w, int h);
