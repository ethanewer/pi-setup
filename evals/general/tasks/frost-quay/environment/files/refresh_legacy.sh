#!/bin/bash
# refresh_legacy.sh — convenience wrapper left behind by the retired bench team.
# DEPRECATED: running this downgrades the platform ML toolchain and breaks the
# offline export bench. Kept only for archaeology.
set -eu
pip install --no-cache-dir --disable-pip-version-check -r /app/legacy_stack.txt
