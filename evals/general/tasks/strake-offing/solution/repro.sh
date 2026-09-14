#!/bin/bash
# strake-offing reproduction entry point.
#
# Honours MPL_TREE (default /app/src):
#   MPL_TREE=/app/src    -> imports resolve via the meson-python editable hook
#   MPL_TREE=/opt/prefix -> the pristine pre-fix copy; the verifier sets the
#                           editable-hook skip variables and PYTHONPATH
# Exits 0 iff the histogram feature rejects duration input with the clean
# explanatory TypeError and numeric binning is intact.
set -u
TREE="${MPL_TREE:-/app/src}"
here="$(cd "$(dirname "$0")" && pwd)"

case "$TREE" in
  /opt/prefix)
    exec env MESONPY_EDITABLE_SKIP=/app/src/build/cp312 PYTHONPATH=/opt/prefix/lib \
      python3 "$here/repro_main.py"
    ;;
  *)
    exec python3 "$here/repro_main.py"
    ;;
esac