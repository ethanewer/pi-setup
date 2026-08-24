#!/bin/bash
set -euo pipefail

cat > /app/answer.json <<'EOF'
{
  "func1": "cdecl",
  "func2": "stdcall",
  "stack_cleaner_func1": "caller",
  "stack_cleaner_func2": "callee"
}
EOF
echo "wrote answer.json"