#!/bin/bash
set -euo pipefail
cat > /app/run.py <<'PYEOF'
import json
from transformers import AutoTokenizer
t = AutoTokenizer.from_pretrained('/app/tiny_model')
ids = t('hello world')['input_ids']
json.dump(ids, open('/app/toks.json', 'w'))
PYEOF
python3 /app/run.py