# hidden case: stale gate left behind with wrong ownership and a bogus seal
rm -rf /var/lib/snapshotd/gate
mkdir -p /var/lib/snapshotd/gate
chown dana:dana /var/lib/snapshotd/gate
chmod 0700 /var/lib/snapshotd/gate
echo 'bogus-stale-seal' > /var/lib/snapshotd/gate/nightly-rotator.seal
rm -f /app/ops-report.txt
printf 'ledger-cycle:RR-2210\n' > /opt/quarry-vault/rotating/ledger.bin
chown root:root /opt/quarry-vault/rotating/ledger.bin && chmod 0600 /opt/quarry-vault/rotating/ledger.bin
