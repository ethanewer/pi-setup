FROM bench-base:ubuntu-24.04

WORKDIR /app

# Headless X11 server (Xvfb) plus a client utility (xdpyinfo/xwininfo).
RUN apt-get update && apt-get install -y xvfb x11-utils \
    && rm -rf /var/lib/apt/lists/*