/* Stub implementations backing the compat X11 shim (libX11.so.1). */
#include <X11/Xlib.h>
#include <stddef.h>

struct _XDisplay { int dummy; };
static struct _XDisplay the_display;

Display *XOpenDisplay(const char *name) {
    (void)name;
    return &the_display;
}
int XCloseDisplay(Display *dpy) { (void)dpy; return 0; }
Window XCreateSimpleWindow(Display *dpy, Window parent, int x, int y,
                           unsigned width, unsigned height,
                           unsigned border_width, unsigned long border,
                           unsigned long background) {
    (void)dpy; (void)parent; (void)x; (void)y;
    (void)width; (void)height; (void)border_width; (void)border; (void)background;
    return 1;
}
Status XStoreName(Display *dpy, Window w, const char *name) {
    (void)dpy; (void)w; (void)name; return 0;
}
int XFlush(Display *dpy) { (void)dpy; return 0; }
int XDestroyWindow(Display *dpy, Window w) { (void)dpy; (void)w; return 0; }
int DefaultScreen(Display *dpy) { (void)dpy; return 0; }
Window RootWindow(Display *dpy, int scr) { (void)dpy; (void)scr; return 2; }
unsigned long BlackPixel(Display *dpy, int scr) { (void)dpy; (void)scr; return 0; }
unsigned long WhitePixel(Display *dpy, int scr) { (void)dpy; (void)scr; return 1; }
