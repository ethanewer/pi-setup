#!/bin/bash
# Hidden case h1: extreme-probability sweep. The upstream regression test uses
# probabilities 0, 1 and 1e-40 with min_samples 10 and 1000; this case probes
# the same budget computation from probabilities and min_samples the upstream
# test does not use, asserting exact positive-integer budgets.
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
if [ "${SKIMAGE_PRESTINE:-}" = "1" ]; then
    # pristine pre-fix package under /opt/prefix: the meson editable meta
    # finder must not shadow it, so run without site machinery.
    PYTHONPATH=/opt/prefix:/usr/local/lib/python3.12/site-packages \
        exec python3 -S "$DIR/check.py"
else
    cd /tmp && exec python3 "$DIR/check.py"
fi