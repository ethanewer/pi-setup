#!/usr/bin/env bash
# Container entrypoint: start the Halden Grid Postgres scenario, then run.
set -euo pipefail
/opt/gridctl/dbctl.sh up
exec "$@"
