/* Minimal local Xlib shim used by the legacy tree so that the WITH-X build
 * links. This is NOT the real X11 library; it only provides the few symbols
 * gui/xfront.c references. The headless build never touches any of this. */
#pragma once

typedef struct _XDisplay Display;
typedef unsigned long XID;
typedef XID Window;
typedef int Bool;
typedef int Status;

#define True  1
#define False 0

typedef struct {
    unsigned long flags;
    unsigned long background_pixel;
} XSetWindowAttributes;

extern Display *XOpenDisplay(const char *name);
extern int XCloseDisplay(Display *dpy);
extern Window XCreateSimpleWindow(Display *dpy, Window parent, int x, int y,
                                  unsigned width, unsigned height,
                                  unsigned border_width,
                                  unsigned long border,
                                  unsigned long background);
extern Status XStoreName(Display *dpy, Window w, const char *name);
extern int XFlush(Display *dpy);
extern int XDestroyWindow(Display *dpy, Window w);
extern int DefaultScreen(Display *dpy);
extern Window RootWindow(Display *dpy, int scr);
extern unsigned long BlackPixel(Display *dpy, int scr);
extern unsigned long WhitePixel(Display *dpy, int scr);
