#!/usr/bin/env bash
# Container entrypoint: start the Postgres scenario, then run the real command.
set -euo pipefail
/opt/wardctl/dbctl.sh up
exec "$@"