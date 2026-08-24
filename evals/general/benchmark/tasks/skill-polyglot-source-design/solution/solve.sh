#!/bin/bash
set -euo pipefail

cat > /app/polyglot <<'P'
#!/bin/bash
"exec" "python3" "$0"
print("42")
P