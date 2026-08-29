#!/usr/bin/env bash
# Oracle for the hollow-notch task.
#
# Does the REAL sysadmin work to provision the container and install the
# deliverables, exactly as a correct agent would:
#   1. install the canonical provisioner as /app/setup.sh,
#   2. run it against the default site descriptor to bring the cluster up,
#      fix name resolution, produce /app/status.json, and deliver list mail.
#
# Never reads /tests; uses literal /app paths. Re-runnable / idempotent.
set -euo pipefail

cp /solution/setup.sh /app/setup.sh
chmod 755 /app/setup.sh

bash /app/setup.sh /app/palisade/site.conf

echo "palisade provisioned; status written and list mail delivered" >&2