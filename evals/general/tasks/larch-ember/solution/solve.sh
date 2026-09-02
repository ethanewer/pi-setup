#!/bin/bash
# Oracle for larch-ember: author the idempotent provisioning script that goes
# through the ops->sudo->sealctl escalation path, then RUN it so the vault is
# genuinely provisioned. Never reads /tests.
set -euo pipefail

cat > /app/provision.sh <<'PROV'
#!/usr/bin/env bash
# Idempotent provisioning for the larch-ember sealing appliance.
# All privileged work happens as user `ops` through the configured sudo rule
# on /usr/local/bin/sealctl; nothing is written to the vault directly as root.
set -uo pipefail

SEALCTL=/usr/local/bin/sealctl
LOG=/app/provision.log

esc() {
    # run sealctl as root, entered via the unprivileged account ops + its
    # passwordless sudo rule (the only configured elevation path)
    runuser -u ops -- sh -c "sudo -n $SEALCTL $*" || return 1
}

: > "$LOG"
echo "larch-ember seal provision report - $(date -u +%FT%TZ)" >> "$LOG"

esc seal ledger-primary 7f3a   >> "$LOG" 2>&1
esc seal ledger-audit   9c02   >> "$LOG" 2>&1
esc prune ledger-primary ledger-audit >> "$LOG" 2>&1

echo "sealed ledger-primary via sudo sealctl" >> "$LOG"
echo "sealed ledger-audit via sudo sealctl" >> "$LOG"
echo "pruned stale seals via sudo sealctl prune" >> "$LOG"

echo "provisioning complete"
exit 0
PROV
chmod +x /app/provision.sh

/app/provision.sh
