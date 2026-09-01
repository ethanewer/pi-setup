#!/usr/bin/env bash
set -euo pipefail

cat > /app/browser_answers.json <<'JSON_END'
{"q1":"true","q2":"true","q3":"DOMContentLoaded","q4":"true","q5":"true","q6":"true","q7":"false","q8":"false"}
JSON_END
