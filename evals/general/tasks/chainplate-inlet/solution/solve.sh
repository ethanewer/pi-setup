#!/bin/bash
# Oracle for chainplate-inlet: applies the upstream-shaped fix to the
# statsmodels checkout at /app/src (MixedLMResults.summary() must honor the
# caller's title argument), reinstalls the package from the repaired tree,
# and proves the fix by running the project's own test module for the feature
# (extracted from the fix release into /opt/golden, including the upstream
# regression test test_summary_title) and the reproduction snippet.
set -euo pipefail

python3 /solution/fix_title.py /app/src/statsmodels/regression/mixed_linear_model.py

echo "== resulting diff (stat) =="
git -C /app/src diff --stat
git -C /app/src diff | sed 's/^/    /' | head -40

echo "== rebuild + reinstall from the repaired tree =="
cd /app/src
pip install --no-build-isolation --no-deps --no-cache-dir --disable-pip-version-check \
    --config-settings=builddir=/opt/sm-build . >/dev/null

echo "== the project's own test module for the feature (golden, incl. test_summary_title) =="
cd /tmp && python3 -m pytest -q -p no:cacheprovider /opt/golden/test_lme.py

echo "== reproduction after the fix =="
python3 /app/probe_title.py

echo "== oracle done =="