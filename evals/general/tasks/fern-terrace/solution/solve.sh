#!/bin/bash
# Oracle: install the builder as the deliverable and run a full E2E guest bring-up
# for the visible profile, leaving the emulator running.
set -e
cp "$(dirname "$0")/build_guest.sh" /app/build_guest.sh
chmod +x /app/build_guest.sh

cat > /app/profile.json <<'JSON'
{
  "hostname": "fringe-north",
  "password": "zephyr-willow-2291",
  "port": 2720,
  "service_token": "fern-terrace-morning-mist-4811",
  "disk": "",
  "marker_path": "/media/data/marker",
  "marker_expected": "wpb-fernterrace-seed-1024"
}
JSON

bash /app/build_guest.sh /app/profile.json /app

# the builder must have produced the declared deliverables in /app
for f in /app/guest.iso /app/serial.log; do
    if [ ! -f "$f" ]; then echo "missing deliverable $f" >&2; exit 1; fi
done
grep -q FERN-BOOT-READY /app/serial.log || { echo "serial.log lacks FERN-BOOT-READY" >&2; exit 1; }
echo "SOLVE_DONE ok"
