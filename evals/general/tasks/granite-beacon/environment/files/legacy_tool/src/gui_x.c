/* The X11 graphical frontend.  Only compiled when ENABLE_GUI is ON. */
#include <X11/Xlib.h>
#include <stdio.h>
#include "core.h"

int main(void) {
    Display *d = XOpenDisplay(NULL);
    if (!d) {
        fprintf(stderr, "transwc: cannot open X display\n");
        return 1;
    }
    XSync(d, 0);
    XCloseDisplay(d);
    return 0;
}