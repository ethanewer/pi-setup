#!/bin/bash
# solve.sh — oracle for cinder-guest.
#
# Produces the two deliverables the contract requires by doing the real work:
#   1. /app/run.sh        — the emulator driver (successful implementation)
#   2. /app/result.json   — produced by RUNNING run.sh on the main scenario
# The emulator is left running in the background as a persistent service.
set -euo pipefail

install -m 0755 /solution/run.sh /app/run.sh
cp /solution/scenario-main.json /app/scenario-main.json

# Execute the driver for the main scenario; it boots the guest, drives the
# guest's serial shell over the redirected TCP port, verifies the monitor,
# writes /app/result.json, and leaves qemu running in the background.
bash /app/run.sh /app/scenario-main.json /app

echo "solve.sh: deliverables produced:"
ls -la /app/run.sh /app/result.json /app/serial.txt /app/monitor.txt 2>/dev/null
echo "solve.sh: emulator left running in background."