FROM bench-base:ubuntu-24.04

WORKDIR /app

# nginx is the reverse-proxy / static front that serves the noVNC landing page
# and proxies the /ws WebSocket path onward to the websockify bridge.
RUN apt-get update && \
    apt-get install -y nginx && \
    rm -rf /var/lib/apt/lists/*

COPY files/ /app/