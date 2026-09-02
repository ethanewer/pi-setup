/* X11 frontend for plotsmith. Compiled only when the build is configured
 * WITH X support; it is excluded entirely from the headless build. */
#include <X11/Xlib.h>

#include "../core/front.h"

void pl_present(const unsigned char *pix, int w, int h) {
    Display *dpy = XOpenDisplay(NULL);
    if (dpy == NULL) return;
    int scr = DefaultScreen(dpy);
    Window win = XCreateSimpleWindow(dpy, RootWindow(dpy, scr),
                                     0, 0, (unsigned)w, (unsigned)h, 1,
                                     BlackPixel(dpy, scr),
                                     WhitePixel(dpy, scr));
    XStoreName(dpy, win, "plotsmith");
    XFlush(dpy);
    XDestroyWindow(dpy, win);
    XCloseDisplay(dpy);
    (void)pix;
}
