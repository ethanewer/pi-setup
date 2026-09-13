#!/bin/bash
# Oracle for capstan-chartroom: applies the zero-row guards to the
# statsmodels checkout at /app/src, reinstalls the package from the repaired
# tree, and proves the fix with the project's own test module for the
# feature, run against the installed library from a scratch directory.
set -euo pipefail

python3 /solution/fix_empty_rows.py /app/src/statsmodels/stats/descriptivestats.py

echo "== rebuild + reinstall from the repaired tree =="
cd /app/src
pip install --no-build-isolation --no-deps --no-cache-dir --disable-pip-version-check \
    --config-settings=builddir=/opt/sm-build . >/dev/null

echo "== project's own test module for the feature =="
rm -rf /tmp/oracle && mkdir -p /tmp/oracle
cp /opt/golden/test_descriptivestats.py /tmp/oracle/
if ! ( cd /tmp/oracle && python3 -m pytest test_descriptivestats.py -q ); then
  echo "oracle: the project's test module does not pass" >&2
  exit 1
fi

echo "== reproduction after the fix =="
cd /tmp && python3 - <<'EOF'
import pandas as pd
from statsmodels.stats.descriptivestats import describe

df = pd.DataFrame({"a": pd.Series([], dtype="float64")})
res = describe(df)
assert (res.loc["nobs"] == 0).all()
assert (res.loc["missing"] == 0).all()
assert res.loc["mean", "a"] != res.loc["mean", "a"]

dfc = pd.DataFrame({"a": pd.Series([], dtype="category")})
resc = describe(dfc)
assert (resc.loc["nobs"] == 0).all()
assert (resc.loc["missing"] == 0).all()
print("oracle: zero-row frames now return NaN/zero summaries")
EOF

echo "== oracle done =="