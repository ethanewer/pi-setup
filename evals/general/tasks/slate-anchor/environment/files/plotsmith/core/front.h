#pragma once

/* Frontend presentation hook. The headless build provides a no-op; the X11
 * build (gui/xfront.c) blits the canvas to an X window. */
void pl_present(const unsigned char *pix, int w, int h);
