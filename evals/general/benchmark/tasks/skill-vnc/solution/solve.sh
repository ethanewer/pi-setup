#!/bin/bash
set -euo pipefail

cat > /app/vnc_answer.txt <<'EOF'
VNC uses the RFB (Remote Framebuffer) protocol. VNC servers conventionally listen on TCP port 5900. A VNC client displays the remote host's desktop framebuffer, and the protocol transmits pixel updates from server to client.
EOF