#!/bin/bash
# Oracle for capstan-current: applies the minimal upstream fix to the
# syncthing checkout at /app/src (add the empty-string guard to the UPnP
# control-URL path normalization), then rebuilds and runs the project's own
# regression case against the repaired tree.
set -e

python3 /solution/fix_upnp.py /app/src/lib/upnp/upnp.go

echo "== running the project's regression case =="
cd /app/src && go test ./lib/upnp/ -run TestControlURLParsingQueryOnly -v