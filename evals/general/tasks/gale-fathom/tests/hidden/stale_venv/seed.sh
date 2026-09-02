#!/bin/bash
# Edge: /app/env/.venv exists but holds the OUTDATED fathom_core 1.3.0 (which has
# no gale_math dependency and returns a different ramp) and /app/pinned.txt lists
# the wrong pin. Provisioner must repair the venv to the pinned 2.4.0 and rewrite
# the lock file to match.
rm -rf /app/env
python3 -m venv /app/env/.venv
/app/env/.venv/bin/pip install -q --no-index --find-links=/opt/gale-index 'fathom_core==1.3.0'
echo 'fathom_core==1.3.0' > /app/pinned.txt
