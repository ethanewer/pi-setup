#!/bin/bash
set -euo pipefail

# Create the agent-facing forward script.  It clears any stale listener on the
# forward port, then launches a background socat tunnel (8090 -> 9097) and
# returns immediately.
cat > /app/forward.sh <<'SH'
#!/bin/bash
if command -v fuser >/dev/null 2>&1; then
  fuser -k 8090 2>/dev/null || true
fi
nohup socat TCP-LISTEN:8090,fork,reuseaddr TCP:127.0.0.1:9097 >/dev/null 2>&1 &
exit 0
SH
chmod +x /app/forward.sh