#!/bin/bash
# Hidden case h2: boundary invariants and exact-value checks. The upstream
# regression test pins the clipping behaviour for (1,100,10) and (1,100,1000);
# this case checks boundary semantics that a crude repair could break (the
# probability==0 shortcut, the n_inliers==0 infinity), exact agreement with the
# independent log formula for ordinary inputs the upstream test does not use,
# and exact tiny-probability budgets the upstream test does not use.
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
if [ "${SKIMAGE_PRESTINE:-}" = "1" ]; then
    PYTHONPATH=/opt/prefix:/usr/local/lib/python3.12/site-packages \
        exec python3 -S "$DIR/check.py"
else
    cd /tmp && exec python3 "$DIR/check.py"
fi