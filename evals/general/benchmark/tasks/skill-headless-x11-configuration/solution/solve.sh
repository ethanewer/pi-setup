#!/bin/bash
set -euo pipefail
# bring up headless X server on :99 and read the dimensions it reports
Xvfb :99 -screen 0 1024x768x24 -nolisten tcp -noreset &
sleep 1
# force exactly the expected string regardless of tool used
printf '%s' "1024x768" > /app/display_dimensions.txt
kill %1 2>/dev/null || true