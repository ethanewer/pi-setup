#!/bin/bash
set -euo pipefail

cat > /app/websockify_answer.txt <<'EOF'
websockify is a tool that bridges WebSocket traffic to plain TCP. It lets browsers connect to a VNC server over a WebSocket connection, forwarding frames to the underlying TCP port. noVNC is an in-browser HTML5 VNC client that runs entirely in JavaScript over WebSocket, so no native VNC client is needed. The browser connects to websockify over varous ports, commonly 6080.
EOF