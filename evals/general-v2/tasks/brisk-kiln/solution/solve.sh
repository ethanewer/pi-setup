#!/bin/bash
#
# brisk-kiln oracle. Does the real work: authors the required listd
# configuration as /app/lists.conf, writes the idempotent installer
# /app/install.sh, and runs it so the config lands at the canonical path and
# the daemon is serving. Never reads /tests.
set -euo pipefail

CONF="/app/lists.conf"
INSTALLER="/app/install.sh"

# ---- 1. The configuration deliverable.
cat > "$CONF" <<'EOF'
[global]
hostname = lists.grebe-lake.net
spool = /var/spool/listd
port = 8418

[list.announce]
owner = ops@grebe-lake.net
closed = true
members = ops@grebe-lake.net, warden@grebe-lake.net

[list.chatter]
owner = rosa@grebe-lake.net
closed = false
members = rosa@grebe-lake.net, finn@example.org

[list.alerts]
owner = ops@grebe-lake.net
closed = true
members = ops@grebe-lake.net
EOF

# ---- 2. The idempotent installer deliverable.
cat > "$INSTALLER" <<'EOF'
#!/bin/bash
set -euo pipefail
install -d -m 0755 /etc/listd
cp /app/lists.conf /etc/listd/lists.conf
/opt/listd/ctl.sh restart
EOF
chmod +x "$INSTALLER"

# ---- 3. Run the installer: canonical path + running daemon (the real work).
bash "$INSTALLER"

# ---- 4. Sanity: daemon is healthy with the canonical config.
for _ in $(seq 1 25); do
  if python3 - <<'PY' 2>/dev/null
import urllib.request, json
with urllib.request.urlopen("http://127.0.0.1:8418/health", timeout=2) as r:
    body = json.load(r)
    assert body.get("status") == "ok"
PY
  then
    echo "brisk-kiln oracle complete -> $CONF and $INSTALLER (daemon healthy)"
    exit 0
  fi
  sleep 0.2
done

echo "oracle: listd did not become healthy" >&2
exit 1
