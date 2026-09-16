#!/bin/bash
# Compatibility entry point for shared candidate QA.
# Usage: bash tools/rebuild_and_audit.sh --candidate PATH --review PATH
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tools/rebuild_and_audit.py "$@"
