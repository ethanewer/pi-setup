#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cp "$script_dir/manifest_audit.py" /app/manifest_audit.py
chmod 755 /app/manifest_audit.py
