#!/usr/bin/env bash
# hidden case: already-configured state (idempotent re-entry).
# Every target already exists in its final form; re-running the fix must leave
# it intact and still pass. Also probes a pre-existing token and a vault file
# that is already gone.
set -u
source /tests/lib.sh

# already-correct setgid dir
mkdir -p /srv/team/shared
chown :devteam /srv/team/shared && chmod 2775 /srv/team/shared

# scripts already stripped
chmod a-x "$F1" "$F2"

# archive already normalized, token already minted
rm -f "$ARCH"
if [ -d /app/build-src ]; then
  find /app/build-src -type d -exec chmod 700 {} +
  find /app/build-src -type f -exec chmod 600 {} +
  tar -C /app/build-src --owner=0 --group=0 --mtime='2000-01-01 00:00:00' -cf "$ARCH" .
fi
runuser -u alice -- sudo -n /opt/objsvc/bridge token atlas-client >/dev/null 2>&1 || true

bash /app/fix.sh || { echo "case-1: fix.sh failed"; exit 1; }
if check_final_state; then exit 0; else exit 1; fi