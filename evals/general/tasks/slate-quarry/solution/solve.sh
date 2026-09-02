#!/bin/bash
# slate-quarry oracle: author the rotation script deliverable, then execute it
# exactly the way the verifier does (as the unprivileged user dana) so the
# privileged effects genuinely go through the configured sudo rule.
set -eu

cat > /app/ops.sh <<'SH'
#!/bin/bash
# slate-quarry nightly rotation. Runs as dana; every privileged effect is
# obtained through the configured passwordless sudo rule.
set -u

REPORT=/app/ops-report.txt
SEAL_NAME=nightly-rotator
SNAP=/usr/local/bin/snapshotctl
LEDGER=/opt/quarry-vault/rotating/ledger.bin

# 1) mint the rotation seal through the sudo-allowed snapshotctl (root gate).
sudo "$SNAP" seal "$SEAL_NAME" || exit 1
sudo "$SNAP" verify "$SEAL_NAME" || exit 1

# 2) destroy the protected ledger through the sudo-allowed shred rule.
if [ -e "$LEDGER" ]; then
  sudo /usr/bin/shred -u "$LEDGER" || exit 1
fi

# 3) rewrite the report from scratch (idempotent, owned by the dana run).
rm -f "$REPORT"
{
  echo "slate-quarry ops report - $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "SEAL: sudo $SNAP seal $SEAL_NAME"
  echo "SEALVERIFY: sudo $SNAP verify $SEAL_NAME"
  echo "DESTROY: sudo /usr/bin/shred -u $LEDGER"
} > "$REPORT"

echo "ops complete"
SH
chmod 0755 /app/ops.sh

# Execute the deliverable as the unprivileged operator (as the grader does).
su -s /bin/bash dana -c 'bash /app/ops.sh'

echo "solve.sh done -> /app/ops.sh and /app/ops-report.txt"
ls -l /app/ops.sh /app/ops-report.txt
