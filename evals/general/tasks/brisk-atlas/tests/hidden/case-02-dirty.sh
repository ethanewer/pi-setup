#!/usr/bin/env bash
# hidden case: deliberately dirty/malformed starting state.
# The fix must recover a messed-up workspace, re-normalize an archive whose
# members carry rogue owners/modes/times, re-strip scripts and re-remove a
# re-added protected file, restore the ... setgid group, re-mint the token and
# re-open the bucket ACL.
set -u
source /tests/lib.sh

# shared dir exists but wrong group + no setgid
mkdir -p /srv/team/shared
chown :root /srv/team/shared && chmod 0755 /srv/team/shared

# rogue archive members (uid 1234, mode 0644/0777, 1999 stamp)
rm -rf /tmp/messy && mkdir -p /tmp/messy/pkg
printf 'x\n' > /tmp/messy/pkg/data.bin && printf 'y\n' > /tmp/messy/notes.txt
chmod 0644 /tmp/messy/pkg/data.bin && chmod 0777 /tmp/messy/notes.txt
touch -d '1999-12-31 23:59:59' /tmp/messy/pkg/data.bin
tar -C /tmp/messy --owner=1234 --group=1234 -cf /app/workspace.tar .

# scripts back to executable
chmod 0755 "$F1" "$F2"

# protected file re-added
mkdir -p /opt/secret/root
printf 'rogue\n' > /opt/secret/root/client.bin && chmod 0600 /opt/secret/root/client.bin

# token gone; root gate wiped
rm -rf /var/lib/brk/rootgate

# bucket made fully private / world-unreadable
chmod 0700 /app/portable-bucket
setfacl -b /app/portable-bucket 2>/dev/null || true

bash /app/fix.sh || { echo "case-2: fix.sh failed"; exit 1; }
if check_final_state; then exit 0; else exit 1; fi