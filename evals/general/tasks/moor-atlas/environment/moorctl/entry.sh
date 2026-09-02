#!/usr/bin/env bash
# Container entrypoint: bring up both Postgres clusters, then run the command.
set -euo pipefail
/opt/moorctl/dbctl.sh up
exec "$@"
