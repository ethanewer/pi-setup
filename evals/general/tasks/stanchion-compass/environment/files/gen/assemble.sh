#!/bin/bash
# Build-time assembly for stanchion-compass: generate the heavy data modules.
set -eu
cd /app
python3 /app/gen/make_data.py
echo "assemble: heavy data modules generated under /app/src/lib"