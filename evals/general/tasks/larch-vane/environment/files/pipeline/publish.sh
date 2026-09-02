#!/usr/bin/env bash
# larch-vane chain entry point.
# usage: publish.sh <recordings-dir> <report-json>
# Calls the two stages DIRECTLY, so the whole chain requires the executable
# bit on every script in this directory.
set -euo pipefail
export LC_ALL=C

if [ "$#" -ne 2 ]; then
  echo "usage: publish.sh <recordings-dir> <report-json>" >&2
  exit 2
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
STAGE="$(mktemp -d /tmp/larch-vane-stage.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

"$HERE/ingest.sh" "$1" "$STAGE"
"$HERE/enrich.sh" "$STAGE" "$2"
echo "PUBLISH_OK"
