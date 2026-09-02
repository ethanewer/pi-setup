# hidden case: gate wiped entirely, ledger replaced with fresh content, report gone
rm -rf /var/lib/snapshotd/gate
rm -f /app/ops-report.txt
printf 'ledger-cycle:ZQ-1093\ncarrier=slate-55110\n' > /opt/quarry-vault/rotating/ledger.bin
chown root:root /opt/quarry-vault/rotating/ledger.bin && chmod 0600 /opt/quarry-vault/rotating/ledger.bin
