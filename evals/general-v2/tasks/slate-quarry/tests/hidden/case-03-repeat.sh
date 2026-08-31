# hidden case: the deliverable must be idempotent across back-to-back runs
rm -f /app/ops-report.txt
printf 'ledger-cycle:TT-3341\n' > /opt/quarry-vault/rotating/ledger.bin
chown root:root /opt/quarry-vault/rotating/ledger.bin && chmod 0600 /opt/quarry-vault/rotating/ledger.bin
su -s /bin/bash dana -c 'bash /app/ops.sh' >/dev/null 2>&1 || exit 1
