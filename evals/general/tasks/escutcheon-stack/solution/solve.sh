#!/usr/bin/env bash
# Oracle for escutcheon-stack (executes-deliverable).
#
# Installs the real solver as /app/stack/deploy.sh and proves it on a throwaway
# snapshot, leaving the shipped /app/stack/live fixture pristine. The verifier
# independently re-runs /app/stack/deploy.sh against hidden snapshots. Never
# reads /tests.
set -euo pipefail

cp /solution/deploy.sh /app/stack/deploy.sh
chmod +x /app/stack/deploy.sh

# Smoke-run the solver once on a temp snapshot (adopt the shipped live files in
# a copy) to prove the deliverable works end to end.
smoke=/tmp/es_oracle_smoke
rm -rf "$smoke"
mkdir -p "$smoke"
cp -r /app/stack/live "$smoke/live"

/app/stack/deploy.sh "$smoke"

echo "oracle installed and smoke-tested /app/stack/deploy.sh"
exit 0
