#!/bin/bash
# Hidden seed 1: the compiled package + the numeric library are stripped out
# again and the broken stub put back, plus the tiny helper is gone. repair.sh
# must re-install everything from source/wheels and restore the native backend.
set -euo pipefail
PY="$(command -v python3)"
SP="$("$PY" -c "import sysconfig;print(sysconfig.get_paths()['purelib'])")"

"$PY" -m pip uninstall -y -q onyxprism prism 2>/dev/null || true
"$PY" -m pip uninstall -y -q numpy 2>/dev/null || true

rm -rf "$SP/onyxprism" "$SP/prism"
mkdir -p "$SP/onyxprism"
printf "raise ImportError('onyxprism native backend unavailable (stub)')\n" > "$SP/onyxprism/__init__.py"
echo "seed1 applied"