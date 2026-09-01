#!/bin/bash
# Hidden seed 3: pip is REMOVED again, the compiled package + numeric library
# are stripped, and the stub re-inserted. repair.sh must re-bootstrap pip from
# the official get-pip.py (not a system/lazily-left copy) and reinstall the
# rest from clean states.
set -euo pipefail
PY="$(command -v python3)"
SP="$("$PY" -c "import sysconfig;print(sysconfig.get_paths()['purelib'])")"

"$PY" -m pip uninstall -y -q onyxprism prism 2>/dev/null || true
"$PY" -m pip uninstall -y -q numpy 2>/dev/null || true
"$PY" -m pip uninstall -y -q pip 2>/dev/null || true

rm -rf "$SP/onyxprism" "$SP/prism"
mkdir -p "$SP/onyxprism"
printf "raise ImportError('onyxprism native backend unavailable (stub)')\n" > "$SP/onyxprism/__init__.py"
echo "seed3 applied"