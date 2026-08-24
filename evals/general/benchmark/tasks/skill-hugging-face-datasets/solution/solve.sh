#!/bin/bash
set -euo pipefail
cat > /app/filter.py <<'PYEOF'
from datasets import load_dataset
ds = load_dataset('json', data_files='/app/data.jsonl')['train']
good = ds.filter(lambda ex: ex['quality'] == 'good')
open('/app/count.txt', 'w').write(str(len(good)))
PYEOF
python3 /app/filter.py