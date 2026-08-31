#!/usr/bin/env bash
# larch-vane stage 1: normalize raw recordings into a staging directory.
# usage: ingest.sh <recordings-dir> <staging-dir>
set -euo pipefail
export LC_ALL=C

if [ "$#" -ne 2 ]; then
  echo "usage: ingest.sh <recordings-dir> <staging-dir>" >&2
  exit 2
fi

SRC="$1"
DST="$2"
mkdir -p "$DST"

for f in "$SRC"/*.log; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  awk -F',' '
    NF == 3 {
      for (i = 1; i <= 3; i++) {
        gsub(/^[ \t]+/, "", $i)
        gsub(/[ \t]+$/, "", $i)
      }
      if ($1 ~ /^[A-Za-z0-9_-]+$/ && $2 ~ /^-?[0-9]+$/ && $3 ~ /^-?[0-9]+$/)
        print $1 "," $2 "," $3
    }
  ' "$f" > "$DST/$base"
done

echo "INGEST_OK"
