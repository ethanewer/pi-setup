This container has no physical display, but X11 applications can still run against a **headless** X server provided by Xvfb (a software virtual framebuffer).

Configure a headless X11 display server and verify the screen it reports.

1. Start an Xvfb display server on display `:99` with a 1024x768 screen at 24 bits per pixel, for example:
   ```
   Xvfb :99 -screen 0 1024x768x24 &
   ```
2. Connect to it with an X11 client tool and read the screen/root geometry, for example:
   ```
   xdpyinfo -display :99
   ```
   or
   ```
   xwininfo -root -display :99
   ```
   The screen must report 1024x768 pixels.
3. Write the reported dimensions to `/app/display_dimensions.txt` as exactly the string `1024x768` (nothing else).

The verifier checks that `/app/display_dimensions.txt` equals `1024x768`, proving a headless Xvfb server of the requested size was configured and queried.