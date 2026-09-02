#!/usr/bin/env bash
# Hidden case: everything removed / edge-absent targets.
# The fix must recreate the shared dir from scratch, rebuild the runtime gate,
# recreate audit.txt, re-append the rc env block, strip freshly-made launchers
# that are marked world-executable, and grant public read on a bucket that had
# a conflicting user+mask capture.
set -u
source /tests/lib.sh

# wipe shared dir entirely
rm -rf /srv/team/shared /srv/team
# wipe audit deliverable
rm -f /app/audit.txt
# wipe the root gate & token
rm -rf /var/lib/brk/rootgate
# wipe the rc env block
> "$RC"

# freshly re-executed launchers (original bytes restored, now world-exec)
chmod 0777 "$F1" "$F2"
rm -f /run/brisk-deprecated-ran /run/brisk-legacy-ran

# bucket: locked to a private user+mask capture
chmod 0000 "$BUCKET"
setfacl -m u:alice:rwx "$BUCKET" 2>/dev/null || true
setfacl -m m::rwx "$BUCKET" 2>/dev/null || true

# protected file back
mkdir -p /opt/secret/root
printf 'x\n' > /opt/secret/root/client.bin
chmod 0600 /opt/secret/root/client.bin

bash /app/fix.sh || { echo "case-3: fix.sh failed"; exit 1; }
if check_final_state; then exit 0; else exit 1; fi