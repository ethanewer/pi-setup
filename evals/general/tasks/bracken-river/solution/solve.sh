#!/bin/bash
# Oracle for bracken-river: install R offline from the vendored deb bundle,
# wire settings.json to the real Rscript, write the idempotent installer
# deliverable, and run the pipeline end-to-end on the visible params.
# Never reads /tests.
set -u

# ---- 1. Write the idempotent offline installer (deliverable).
cat > /app/setup_r.sh <<'EOF'
#!/usr/bin/env bash
# Idempotent offline installer for the Osprey Ridge R runtime.
# Installs R from the local deb bundle at /app/debs; no network involved.
set -u

if command -v Rscript >/dev/null 2>&1 \
   && Rscript --vanilla -e 'invisible(cat("ok"))' >/dev/null 2>&1; then
    echo "R already available: $(command -v Rscript)"
    exit 0
fi

if [ ! -d /app/debs ] || [ -z "$(ls -A /app/debs 2>/dev/null)" ]; then
    echo "setup_r.sh: offline deb bundle missing at /app/debs" >&2
    exit 1
fi

DEBIAN_FRONTEND=noninteractive dpkg -i /app/debs/*.deb
if ! command -v Rscript >/dev/null 2>&1; then
    echo "setup_r.sh: install failed; Rscript still missing" >&2
    exit 1
fi
echo "R installed: $(command -v Rscript)"
exit 0
EOF
chmod 0755 /app/setup_r.sh

# ---- 2. Install R offline (live repair).
bash /app/setup_r.sh || { echo "oracle: R install failed" >&2; exit 1; }

# ---- 3. Wire settings.json to the resolved absolute Rscript path.
RSCRIPT="$(command -v Rscript)"
[ -n "$RSCRIPT" ] || { echo "oracle: Rscript not on PATH" >&2; exit 1; }
python3 - "$RSCRIPT" <<'PY'
import json, sys
path = sys.argv[1]
with open("/app/pipeline/settings.json") as fh:
    settings = json.load(fh)
settings["rscript"] = path
with open("/app/pipeline/settings.json", "w") as fh:
    json.dump(settings, fh, indent=2)
    fh.write("\n")
PY

# ---- 4. Run the pipeline end to end on the visible params.
python3 /app/pipeline/riverlaunch.py /app/pipeline/params_visible.txt /app/pipeline/selftest.txt \
    || { echo "oracle: pipeline selftest failed" >&2; exit 1; }

echo "solve.sh done"
ls -l /app/setup_r.sh /app/pipeline/settings.json /app/pipeline/selftest.txt
cat /app/pipeline/selftest.txt
