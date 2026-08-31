#!/usr/bin/env bash
# Container entrypoint: start the archive Postgres scenario, then run the real
# command.
set -euo pipefail
/opt/archivectl/dbctl.sh up
exec "$@"
