#!/usr/bin/env bash
# Container entrypoint: start the Fernvale Postgres scenario, then run CMD.
set -euo pipefail
/opt/obsctl/dbctl.sh up
exec "$@"
