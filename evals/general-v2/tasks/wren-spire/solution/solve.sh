#!/usr/bin/env bash
# Oracle for wren-spire: writes the idempotent provisioning deliverable
# /app/setup.sh (which places the canonical listd configuration at
# /etc/listd/lists.conf and makes the running daemon honor it), runs it, and
# captures the daemon's loaded configuration into /app/loaded.json. Never
# reads /tests.
set -euo pipefail

cat > /app/setup.sh <<'EOF'
#!/usr/bin/env bash
# Hollowpine Observatory mailing-list provisioning (idempotent).
set -euo pipefail

install -d -m 0755 /etc/listd

cat > /etc/listd/lists.conf <<'CONF'
[list observers@hollowpine.example]
subscribers = wren@hollowpine.example, sable@hollowpine.example, quill@hollowpine.example

[list announce@hollowpine.example]
subscribers = wren@hollowpine.example, iris@hollowpine.example

[list digest@hollowpine.example]
subscribers =
CONF

# make the running daemon honor the freshly written canonical config
/opt/listd/ctl.sh restart
EOF
chmod 0755 /app/setup.sh

bash /app/setup.sh

# capture the daemon's currently loaded configuration as the second deliverable
/opt/listd/ctl.sh dump > /app/loaded.json

echo "wren-spire oracle done"
ls -l /app/setup.sh /app/loaded.json
