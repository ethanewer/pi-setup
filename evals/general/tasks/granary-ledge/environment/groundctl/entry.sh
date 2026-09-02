#!/usr/bin/env bash
# Container entrypoint: bring up the Postgres scenario, then run the command.
set -euo pipefail
/opt/groundctl/dbctl.sh up
exec "$@"
