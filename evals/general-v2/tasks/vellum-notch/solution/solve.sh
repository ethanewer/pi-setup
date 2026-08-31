#!/bin/bash
# Real oracle for vellum-notch: write the single-member streaming script and
# RUN it on the visible fixture to produce /app/out/build.id. Never reads /tests.
set -eu

SCRIPT="/app/extract_member.sh"
OUT="/app/out/build.id"

cat > "$SCRIPT" <<'SH'
#!/usr/bin/env bash
# Stream one member of a gzip-compressed tar archive to stdout without
# extracting anything to disk.
set -eu
if [ "$#" -ne 2 ]; then
    echo "usage: extract_member.sh <archive.tar.gz> <member-name>" >&2
    exit 2
fi
exec tar -xOzf "$1" "$2"
SH
chmod +x "$SCRIPT"

mkdir -p /app/out
"$SCRIPT" /app/ir/incident.tar.gz manifests/build.id > "$OUT"

echo "solve.sh done -> $SCRIPT and $OUT"
ls -l "$SCRIPT" "$OUT"
