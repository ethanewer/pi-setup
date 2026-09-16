#!/usr/bin/env bash
# Compatibility entry point: the shared QA backend owns new-task acceptance.
set -euo pipefail
exec python3 "$(dirname "$0")/qa_task.py" "$@"
