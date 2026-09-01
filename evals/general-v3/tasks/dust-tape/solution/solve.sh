#!/usr/bin/env bash
# Oracle for dust-tape: install the triage tool and scan the shipped archive
# with it. Never reads /tests.
set -euo pipefail
py=/usr/bin/python3
[ -x "$py" ] || py=python3

install -m 0755 /solution/triage.py /app/triage.py

# Build /app/inventory.json by running the deliverable over every artifact.
$py - <<'PY'
import json, os, subprocess, sys
root = "/app/artifacts"
names = []
for dirpath, _dirnames, filenames in os.walk(root):
    for fn in filenames:
        full = os.path.join(dirpath, fn)
        names.append(os.path.relpath(full, root))
archive = {}
for name in sorted(names):
    full = os.path.join(root, name)
    out = subprocess.run([sys.executable, "/app/triage.py", full],
                         capture_output=True, text=True, check=True)
    archive[name] = json.loads(out.stdout)
inv = {
    "archive": archive,
    "pdp11_files": sorted(n for n, c in archive.items() if c["arch"] == "pdp11"),
    "host_executable_files": sorted(n for n, c in archive.items()
                                    if c["host_executable"]),
}
with open("/app/inventory.json", "w") as fh:
    json.dump(inv, fh, indent=2)
print("inventory:", json.dumps(inv["pdp11_files"]))
PY
echo "solve.sh done"
