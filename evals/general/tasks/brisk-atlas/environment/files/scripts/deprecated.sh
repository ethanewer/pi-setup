#!/usr/bin/env bash
# Legacy node restarter, deprecated after the 2021 network outage.
# Do NOT run this by hand.
echo "brisk: rebooting legacy worker nodes"
touch /run/brisk-deprecated-ran 2>/dev/null || true