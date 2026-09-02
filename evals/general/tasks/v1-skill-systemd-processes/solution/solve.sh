#!/usr/bin/env bash
# Oracle solution: rewrite the unit file with the correct ExecStart.
cat > /app/watcher.service <<'EOF'
[Unit]
Description=Watcher process monitor

[Service]
ExecStart=/app/watcher.sh
Restart=on-failure

[Install]
WantedBy=default
EOF