#!/bin/bash
# Hidden seed 2: the conda environment, its spec, and the compiled rebuild
# artifact are removed together. repair.sh must recreate the spec file, recreate
# the named conda env from that spec, and re-produce the /app/rebuilt artifact.
set -euo pipefail
rm -rf /app/rebuilt /app/env.txt
/opt/miniconda/bin/conda env remove -y -n onyx_env >/dev/null 2>&1 || true
echo "seed2 applied"