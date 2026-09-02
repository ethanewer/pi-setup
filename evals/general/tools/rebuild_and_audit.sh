#!/bin/bash
# Rebuild derived specs and run every gate/audit in fail-closed order.
# Usage: bash tools/rebuild_and_audit.sh [REFERENCE_ROOT]
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tools/rebuild_and_audit.py "$@"
