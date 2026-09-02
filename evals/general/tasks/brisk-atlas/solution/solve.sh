#!/usr/bin/env bash
#
# oracle solution for brisk-atlas
#
# Writes the compliance-fix deliverable script /app/fix.sh, then RUNS it so
# that every target artifact is produced by real work (stat/chmod/tar/sudo/
# setfacl) rather than fabricated.
set -uo pipefail

cat > /app/fix.sh <<'FIXEOF'
#!/usr/bin/env bash
#
# /app/fix.sh - perform the full compliance hardening for the brisk multi-user
# developer box. Safe (idempotent) to run repeatedly from any starting state.
#
# Summary of what it does:
#   1. build a setgid shared dir owned by group devteam (children inherit it)
#   2. normalize archive metadata (owners, perms, timestamps)
#   3. strip execute bits from legacy scripts, leaving them in place, unrun
#   4. remove a root-protected file only through the allowed escalated command
#   5. invoke the SUDO-GRANTED bridge to mint a capability token into a root dir
#   6. make the bucket root publicly readable via a POSIX ACL (all-users "other")
#   7. persist the BRISK_* environment in alice's shell rc
#
set -uo pipefail

GROUP=devteam
SHARED=/srv/team/shared
SCRIPT1=/opt/tools-scripts/deprecated.sh
SCRIPT2=/opt/tools-scripts/legacy.sh
VAULT=/opt/secret/root/client.bin
BRIDGE=/opt/objsvc/bridge
GATE=/var/lib/brk/rootgate
TOKEN_CT=/var/lib/brk/rootgate/atlas-client.token
BUCKET=/app/portable-bucket
ARCH=/app/workspace.tar
SRC=/app/build-src
RC=/home/alice/.bashrc
OUT=/app/audit.txt

: > "$OUT"
log() { printf '%s\n' "$*" >> "$OUT"; }

log "brisk compliance report - $(date -u +%FT%TZ)"

# ---------------------------------------------------------------- 1 setgid
mkdir -p "$SHARED"
chown :"$GROUP" "$SHARED"
chgrp "$GROUP" "$SHARED"
chmod 2775 "$SHARED"
log "setg-dir       $(stat -c '%A %U:%G %n' "$SHARED")"

# -------------------------------------------------- 2 normalize archive meta
rm -f "$ARCH"
[ -d "$SRC" ] || mkdir -p "$SRC"
find "$SRC" -type d -exec chmod 700 {} +
find "$SRC" -type f -exec chmod 600 {} +
find "$SRC" -exec chown root:root {} +
find "$SRC" -exec touch -d '2000-01-01 00:00:00 UTC' {} +
tar -C "$SRC" --owner=0 --group=0 --mtime='2000-01-01 00:00:00' -cf "$ARCH" .
log "archive        $ARCH members=$(tar -tf "$ARCH" | wc -l)"

# --------------------------------------------------------- 3 strip scripts
chmod a-x "$SCRIPT1" 2>/dev/null
chmod a-x "$SCRIPT2" 2>/dev/null
# never executed, only permission-change + presence verified by the auditor
log "scripts        $(stat -c '%n:%a' "$SCRIPT1" 2>/dev/null) $(stat -c '%n:%a' "$SCRIPT2" 2>/dev/null)"

# ---------------------------------------- 4 root vault removal (escalated)
sudo -u alice -- sh -c 'sudo -n /usr/bin/rm -f /opt/secret/root/client.bin' 2>/dev/null \
  || true
if [ -e /opt/secret/root/client.bin ]; then log "vault-remove    STILL-PRESENT"; else log "vault-remove    removed"; fi

# ------------------------------------------- 5 sudo-bridge capability gain
sudo -u alice -- sh -c 'sudo -n /opt/objsvc/bridge token atlas-client' 2>/dev/null \
  || true
if [ -r "$TOKEN_CT" ]; then log "capability      token=$(cat "$TOKEN_CT")"; else log "capability      MISSING"; fi

# ------------------------------------------- 6 bucket public via ACL
setfacl -R -m o:r "$BUCKET" 2>/dev/null || true
setfacl -m d:o:r "$BUCKET"   2>/dev/null || true
log "bucket-acl      $(getfacl -cp "$BUCKET" 2>/dev/null | grep '^other::' | head -n1)"

# ------------------------------------------- 7 persist tool env in rc
if grep -q 'BRISK_HOME' "$RC"; then :; else
  printf '\n# brisk tool environment\nexport BRISK_HOME=/opt/brisk\nexport BRISK_CTL=/opt/brisk/bin/ctl\nexport BRISK_HEADERS=/opt/brisk/share/headers\n' >> "$RC"
fi
log "rc-presence     line=$(grep -c BRISK_HOME "$RC")"

echo "fix.sh done"
FIXEOF

chmod 0755 /app/fix.sh
bash /app/fix.sh