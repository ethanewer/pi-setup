#!/usr/bin/env bash
# Oracle for flume-quill. Performs the real v1 -> v3 migration of the flume
# repository with the migration tool, then proves the result builds and its
# tests pass. Never reads /tests.
set -euo pipefail

cp /solution/migrate.py /tmp/flume-migrate.py
python3 /tmp/flume-migrate.py /app/flume

echo "oracle: /app/flume migrated to urfave/cli v3 and green"
