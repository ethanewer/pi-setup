#!/bin/bash
# Oracle for tasks/vine-inlet.
#
# Repairs and upgrades the hedge venv, then produces the two remaining
# deliverables (pinned.txt and the react-family downgrade in package.json).
# It does the REAL work with literal /app paths; it never reads /tests and
# never uses a precomputed answer.
set -eu

VENVPY=/app/env/.venv/bin/python
WHEELS=/app/garden_wheel

# 1) Repair the broken pip inside the venv (pip module was removed, ensurepip
#    is intact) so this interpreter can install packages again.
$VENVPY -m ensurepip --upgrade >/dev/null

# 2) Upgrade lotusfields 0.7.0 -> 0.9.0 and confirm coreclutch, both from the
#    local flat wheel index (fully offline).
$VENVPY -m pip install --no-index --no-cache-dir \
    --find-links "$WHEELS" \
    "lotusfields==0.9.0" "coreclutch==0.5.0"

# 3) Produce the pinned manifest of the two frozen top-level packages as it is
#    really installed now.
printf 'lotusfields==0.9.0\ncoreclutch==0.5.0\n' > /app/pinned.txt

# 4) Downgrade the react-family in /app/node/package.json (react, react-dom,
#    react-native) to the locked lower versions, leaving the aws-* and @aws-*
#    and @hedge-* entries EXACTLY untouched and the set of package names in
#    dependencies / devDependencies unchanged.
$VENVPY - <<'PY'
import json
path = "/app/node/package.json"
with open(path) as fh:
    data = json.load(fh)
data["dependencies"]["react"] = "18.2.0"
data["dependencies"]["react-dom"] = "18.2.0"
data["devDependencies"]["react-native"] = "0.72.1"
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY

# 5) Sanity: the probe now accepts the dtype_backend keyword and reads a table.
printf 'zone,height,flux\nA,1,1.5\n' > /tmp/becheck.csv
$VENVPY /app/tools/probe.py /tmp/becheck.csv

echo "vine-inlet solve.sh done"