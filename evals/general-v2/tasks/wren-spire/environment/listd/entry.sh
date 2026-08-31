#!/usr/bin/env bash
# Container entrypoint: start the listd daemon, then run the real command.
set -euo pipefail
mkdir -p /var/spool/listd/incoming /var/spool/listd/processed \
         /var/spool/listd/rejected /var/spool/listd/archive \
         /var/spool/listd/mail /var/lib/listd /etc/listd
/opt/listd/ctl.sh start
exec "$@"
