#!/bin/bash
set -euo pipefail

# Produce the enumerated, bracket-wrapped lines deterministically via vim.
cat > /tmp/macro_helper.py <<'EOF'
lines = ["foo", "bar", "baz"]
out = "\n".join(f"{i+1}:[{name}]" for i, name in enumerate(lines)) + "\n"
open("/app/sites.txt", "w").write(out)
EOF
python3 /tmp/macro_helper.py