#!/bin/bash
# Oracle solution for skill-tokenizers.
set -euo pipefail

python3 - <<'PY'
import json, re
text = open("/app/sample.txt", encoding="utf-8").read()  # don't strip
tokens = re.findall(r"[A-Za-z0-9]+|[^A-Za-z0-9]", text)
json.dump({"tokens": tokens, "count": len(tokens)},
          open("/app/tokens.json", "w"))
print("count", len(tokens))
PY
echo "done"