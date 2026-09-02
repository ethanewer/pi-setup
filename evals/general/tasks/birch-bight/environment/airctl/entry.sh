#!/usr/bin/env bash
# Container entrypoint: bring the airshed Postgres scenario up, then run CMD.
set -euo pipefail
/opt/airctl/dbctl.sh up
exec "$@"
